import Foundation

/// One event from ``ClaudeClient/stream(_:)``.
public enum ClaudeStreamEvent: Sendable, Equatable {
    /// A chunk of generated text, in order.
    case textDelta(String)
    /// A completed `tool_use` block (its input JSON is assembled from the
    /// partial deltas and parsed once the block closes).
    case toolUse(id: String, name: String, input: JSONValue)
    /// Generation finished; carries the stop reason when the API sent one.
    case stop(reason: String?)
}

/// A single, small Anthropic Messages API client for the whole atelier.
///
/// - Async/await, `URLSession`-based, zero dependencies.
/// - ``send(_:)`` for one-shot calls, ``stream(_:)`` for SSE streaming.
/// - Vision (base64 image blocks), multi-turn history, system prompts, and
///   forced-tool structured output all ride the same ``ClaudeRequest``.
/// - Errors are typed (``ClaudeError``): bad key, rate limit with
///   retry-after, overloaded, network, decode.
///
/// BYOK: store the user's key with ``KeychainStore`` and build the client
/// per call site — it is a value type, cheap to create.
///
/// ```swift
/// let client = ClaudeClient(apiKey: key)
/// let reply = try await client.send(ClaudeRequest(
///     model: .haiku,
///     system: "Answer in one sentence.",
///     messages: [.user("Why is the sky blue?")]
/// ))
/// print(reply.text)
/// ```
public struct ClaudeClient: Sendable {
    /// The Messages API endpoint (overridable for tests/proxies).
    public var endpoint: URL
    /// The API key sent as `x-api-key`.
    public var apiKey: String
    /// The URLSession used for transport (inject a stubbed one in tests).
    public var session: URLSession
    /// Per-request timeout in seconds.
    public var timeout: TimeInterval

    /// The `anthropic-version` header value.
    public static let apiVersion = "2023-06-01"
    /// The production Messages endpoint.
    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(
        apiKey: String,
        session: URLSession = .shared,
        endpoint: URL = ClaudeClient.defaultEndpoint,
        timeout: TimeInterval = 90
    ) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
        self.timeout = timeout
    }

    // MARK: - Send (non-streaming)

    /// Run one request and return the full decoded response.
    public func send(_ request: ClaudeRequest) async throws -> ClaudeResponse {
        let urlRequest = try makeURLRequest(request, stream: false)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ClaudeError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.network("non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw Self.mapHTTPError(status: http.statusCode, body: data, response: http)
        }
        do {
            return try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding(error.localizedDescription)
        }
    }

    /// Convenience: run one request and return just the joined text.
    /// - Throws: ``ClaudeError/decoding(_:)`` when the response has no text,
    ///   ``ClaudeError/server(type:message:)`` on a safety refusal.
    public func sendText(_ request: ClaudeRequest) async throws -> String {
        let response = try await send(request)
        if response.isRefusal {
            throw ClaudeError.server(type: "refusal", message: "the request was refused by safety classifiers")
        }
        let text = response.text
        guard !text.isEmpty else { throw ClaudeError.decoding("response contained no text") }
        return text
    }

    // MARK: - Stream (SSE)

    /// Run one request with `stream: true` and yield events as they arrive.
    ///
    /// ```swift
    /// for try await event in client.stream(request) {
    ///     if case .textDelta(let chunk) = event { render(chunk) }
    /// }
    /// ```
    public func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        makeStream(request, onUsage: nil)
    }

    /// Same as ``stream(_:)``, plus the call's token usage — the only way to
    /// see prompt-cache hits (`cacheReadInputTokens`) on a streamed call.
    ///
    /// `onUsage` fires once, before the `.stop` event is yielded: the counts
    /// from `message_start` (input + cache) merged with the cumulative ones
    /// from `message_delta` (output). A stream that ends without
    /// `message_delta` reports what it saw at the end.
    ///
    /// ```swift
    /// for try await event in client.stream(request, onUsage: { u in
    ///     print("cache_read=\(u.cacheReadInputTokens ?? 0) cache_write=\(u.cacheCreationInputTokens ?? 0)")
    /// }) { … }
    /// ```
    public func stream(
        _ request: ClaudeRequest,
        onUsage: @escaping @Sendable (ClaudeResponse.Usage) -> Void
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        makeStream(request, onUsage: onUsage)
    }

    private func makeStream(
        _ request: ClaudeRequest,
        onUsage: (@Sendable (ClaudeResponse.Usage) -> Void)?
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request, stream: true)

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: urlRequest)
                    } catch {
                        throw ClaudeError.network(error.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw ClaudeError.network("non-HTTP response")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw Self.mapHTTPError(status: http.statusCode, body: body, response: http)
                    }

                    var parser = SSEParser()
                    var usageReported = false
                    for try await line in bytes.lines {
                        let events = try parser.consume(line: line)
                        if let onUsage, !usageReported, parser.usageIsFinal, let usage = parser.usage {
                            onUsage(usage)
                            usageReported = true
                        }
                        for event in events {
                            continuation.yield(event)
                        }
                    }
                    if let onUsage, !usageReported, let usage = parser.usage {
                        onUsage(usage)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    /// The wire shape of the request body (snake_case keys, nils omitted).
    /// `system` is either a plain string or an array of text blocks.
    private enum SystemField: Encodable {
        case text(String)
        case blocks([ClaudeSystemBlock])

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s): try c.encode(s)
            case .blocks(let b): try c.encode(b)
            }
        }
    }

    private struct Body: Encodable {
        let model: String
        let maxTokens: Int
        let system: SystemField?
        let messages: [ClaudeMessage]
        let temperature: Double?
        let tools: [ClaudeTool]?
        let toolChoice: ClaudeToolChoice?
        let cacheControl: ClaudeCacheControl?
        let stream: Bool?

        private enum CodingKeys: String, CodingKey {
            case model, system, messages, temperature, tools, stream
            case maxTokens = "max_tokens"
            case toolChoice = "tool_choice"
            case cacheControl = "cache_control"
        }
    }

    private func makeURLRequest(_ request: ClaudeRequest, stream: Bool) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ClaudeError.missingAPIKey }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        let body = Body(
            model: request.model.id,
            maxTokens: request.maxTokens,
            system: request.systemBlocks.map(SystemField.blocks) ?? request.system.map(SystemField.text),
            messages: request.messages,
            temperature: request.temperature,
            tools: request.tools,
            toolChoice: request.toolChoice,
            cacheControl: request.cacheControl,
            stream: stream ? true : nil
        )
        // Sorted keys = the same request always encodes to the same bytes.
        // A Swift dictionary (every `JSONValue.object`, i.e. every tool schema)
        // iterates in a per-instance, per-process order, so plain JSONEncoder
        // reshuffles schema keys between builds and launches — and since tools
        // render first in the prompt, one reshuffle invalidates the whole cache.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
    }

    // MARK: - Error mapping

    /// The API's error envelope: `{"type":"error","error":{"type":..,"message":..}}`.
    private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable {
            let type: String?
            let message: String?
        }
        let error: Inner?
    }

    static func mapHTTPError(status: Int, body: Data, response: HTTPURLResponse?) -> ClaudeError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        let message = envelope?.error?.message
            ?? String(data: body, encoding: .utf8).map { String($0.prefix(300)) }
            ?? "unknown error"

        switch status {
        case 401, 403:
            return .invalidAPIKey(message: message)
        case 429:
            let retryAfter = response?
                .value(forHTTPHeaderField: "retry-after")
                .flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 529:
            return .overloaded
        default:
            return .http(status: status, message: message)
        }
    }
}

// MARK: - SSE parsing

/// Incremental parser for the Messages API's server-sent-event stream.
/// Feed it lines; it returns zero or more ``ClaudeStreamEvent``s per line and
/// throws typed errors for in-stream `error` events.
struct SSEParser {
    private enum PendingBlock {
        case text
        case toolUse(id: String, name: String, json: String)
    }

    /// Wire shape of one SSE `data:` payload (only the fields we use).
    private struct Payload: Decodable {
        let type: String
        let index: Int?
        let contentBlock: BlockSpec?
        let delta: Delta?
        let error: ErrorSpec?
        /// `message_start` only: the message shell, whose usage carries the
        /// input and prompt-cache counts.
        let message: MessageSpec?
        /// `message_delta` only: cumulative usage at the end of the message.
        let usage: LenientUsage?

        // Usage can never cost us an event: both wrappers decode a shape they
        // can't read to nil instead of failing the whole payload.
        struct MessageSpec: Decodable {
            let usage: ClaudeResponse.Usage?
            private enum CodingKeys: String, CodingKey { case usage }
            init(from decoder: Decoder) throws {
                usage = try? decoder.container(keyedBy: CodingKeys.self)
                    .decodeIfPresent(ClaudeResponse.Usage.self, forKey: .usage)
            }
        }
        struct LenientUsage: Decodable {
            let value: ClaudeResponse.Usage?
            init(from decoder: Decoder) throws {
                value = try? ClaudeResponse.Usage(from: decoder)
            }
        }

        struct BlockSpec: Decodable {
            let type: String
            let id: String?
            let name: String?
        }
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let partialJSON: String?
            let stopReason: String?

            private enum CodingKeys: String, CodingKey {
                case type, text
                case partialJSON = "partial_json"
                case stopReason = "stop_reason"
            }
        }
        struct ErrorSpec: Decodable {
            let type: String?
            let message: String?
        }

        private enum CodingKeys: String, CodingKey {
            case type, index, delta, error, message, usage
            case contentBlock = "content_block"
        }
    }

    private var pending: [Int: PendingBlock] = [:]

    /// Token usage seen so far (nil until the stream reports any).
    private(set) var usage: ClaudeResponse.Usage?
    /// True once `message_delta` has delivered the final counts.
    private(set) var usageIsFinal = false

    private mutating func record(_ newer: ClaudeResponse.Usage?, final: Bool) {
        guard let newer else { return }
        usage = usage.map { $0.overlaid(by: newer) } ?? newer
        if final { usageIsFinal = true }
    }

    /// Consume one line of the SSE stream.
    mutating func consume(line: String) throws -> [ClaudeStreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payloadString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payloadString.isEmpty || payloadString == "[DONE]" { return [] }
        guard
            let data = payloadString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return [] }

        switch payload.type {
        case "message_start":
            record(payload.message?.usage, final: false)
            return []

        case "content_block_start":
            if let index = payload.index, let block = payload.contentBlock {
                switch block.type {
                case "text":
                    pending[index] = .text
                case "tool_use":
                    pending[index] = .toolUse(id: block.id ?? "", name: block.name ?? "", json: "")
                default:
                    break
                }
            }
            return []

        case "content_block_delta":
            guard let index = payload.index, let delta = payload.delta else { return [] }
            if delta.type == "text_delta", let text = delta.text {
                return [.textDelta(text)]
            }
            if delta.type == "input_json_delta", let partial = delta.partialJSON,
               case .toolUse(let id, let name, let acc) = pending[index] {
                pending[index] = .toolUse(id: id, name: name, json: acc + partial)
            }
            return []

        case "content_block_stop":
            guard let index = payload.index,
                  case .toolUse(let id, let name, let json) = pending.removeValue(forKey: index)
            else {
                if let index = payload.index { pending[index] = nil }
                return []
            }
            let input: JSONValue
            if json.isEmpty {
                input = .object([:])
            } else if let jsonData = json.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
                input = parsed
            } else {
                input = .string(json)
            }
            return [.toolUse(id: id, name: name, input: input)]

        case "message_delta":
            record(payload.usage?.value, final: true)
            if let stop = payload.delta?.stopReason {
                return [.stop(reason: stop)]
            }
            return []

        case "error":
            let type = payload.error?.type ?? "unknown"
            let message = payload.error?.message ?? "unknown"
            if type == "overloaded_error" { throw ClaudeError.overloaded }
            throw ClaudeError.server(type: type, message: message)

        default: // message_stop, ping...
            return []
        }
    }
}

extension ClaudeResponse.Usage {
    /// `newer`'s counts where it has them, ours otherwise — `message_delta`
    /// usage is cumulative but may omit what `message_start` already said.
    func overlaid(by newer: Self) -> Self {
        Self(
            inputTokens: newer.inputTokens ?? inputTokens,
            outputTokens: newer.outputTokens ?? outputTokens,
            cacheCreationInputTokens: newer.cacheCreationInputTokens ?? cacheCreationInputTokens,
            cacheReadInputTokens: newer.cacheReadInputTokens ?? cacheReadInputTokens
        )
    }
}
