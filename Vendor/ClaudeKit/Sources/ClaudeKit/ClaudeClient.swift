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
                    for try await line in bytes.lines {
                        for event in try parser.consume(line: line) {
                            continuation.yield(event)
                        }
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
    private struct Body: Encodable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [ClaudeMessage]
        let temperature: Double?
        let tools: [ClaudeTool]?
        let toolChoice: ClaudeToolChoice?
        let stream: Bool?

        private enum CodingKeys: String, CodingKey {
            case model, system, messages, temperature, tools, stream
            case maxTokens = "max_tokens"
            case toolChoice = "tool_choice"
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
            system: request.system,
            messages: request.messages,
            temperature: request.temperature,
            tools: request.tools,
            toolChoice: request.toolChoice,
            stream: stream ? true : nil
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)
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
            case type, index, delta, error
            case contentBlock = "content_block"
        }
    }

    private var pending: [Int: PendingBlock] = [:]

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
            if let stop = payload.delta?.stopReason {
                return [.stop(reason: stop)]
            }
            return []

        case "error":
            let type = payload.error?.type ?? "unknown"
            let message = payload.error?.message ?? "unknown"
            if type == "overloaded_error" { throw ClaudeError.overloaded }
            throw ClaudeError.server(type: type, message: message)

        default: // message_start, message_stop, ping...
            return []
        }
    }
}
