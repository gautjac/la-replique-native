import Foundation

/// A decoded (non-streaming) Messages API response.
public struct ClaudeResponse: Sendable, Equatable {
    /// One block of the response's `content` array. Unknown block types are
    /// dropped during decoding so new API features never break old apps.
    public enum Block: Sendable, Equatable {
        case text(String)
        case toolUse(id: String, name: String, input: JSONValue)
    }

    /// Token accounting for the call.
    public struct Usage: Sendable, Equatable, Decodable {
        public let inputTokens: Int?
        public let outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    /// The response id (`msg_...`).
    public let id: String
    /// The model that actually served the request (server-side fallbacks may
    /// substitute another id than the one requested).
    public let model: String
    /// Why generation stopped: `end_turn`, `max_tokens`, `tool_use`,
    /// `refusal`...
    public let stopReason: String?
    /// The content blocks, in order.
    public let content: [Block]
    /// Token usage, when reported.
    public let usage: Usage?

    /// Memberwise init, public for testability and manual construction.
    public init(id: String, model: String, stopReason: String?, content: [Block], usage: Usage?) {
        self.id = id
        self.model = model
        self.stopReason = stopReason
        self.content = content
        self.usage = usage
    }

    /// True when a safety classifier refused the request (`stop_reason ==
    /// "refusal"`) — the content is not a real answer.
    public var isRefusal: Bool { stopReason == "refusal" }

    /// All text blocks joined with a newline and trimmed — the "just give me
    /// the answer" accessor.
    public var text: String {
        content
            .compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode the input of the first `tool_use` block (optionally matching a
    /// tool name) into a `Decodable` type — the structured-output accessor.
    ///
    /// ```swift
    /// let match = try response.toolInput(ArtMatch.self, tool: "name_the_echo")
    /// ```
    /// - Throws: ``ClaudeError/decoding(_:)`` when no matching block exists or
    ///   the input doesn't fit `T`.
    public func toolInput<T: Decodable>(_ type: T.Type = T.self, tool name: String? = nil) throws -> T {
        for block in content {
            if case .toolUse(_, let toolName, let input) = block,
               name == nil || toolName == name {
                do {
                    let data = try JSONEncoder().encode(input)
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw ClaudeError.decoding("tool input did not match \(T.self): \(error.localizedDescription)")
                }
            }
        }
        throw ClaudeError.decoding("no tool_use block\(name.map { " named \($0)" } ?? "") in response")
    }
}

extension ClaudeResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
    }

    /// A lenient wire representation of a content block; unknown types decode
    /// to nil fields and are skipped.
    private struct BlockWire: Decodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: JSONValue?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? "",
            model: try c.decodeIfPresent(String.self, forKey: .model) ?? "",
            stopReason: try c.decodeIfPresent(String.self, forKey: .stopReason),
            content: (try c.decodeIfPresent([BlockWire].self, forKey: .content) ?? []).compactMap { wire in
                switch wire.type {
                case "text":
                    return .text(wire.text ?? "")
                case "tool_use":
                    return .toolUse(id: wire.id ?? "", name: wire.name ?? "", input: wire.input ?? .object([:]))
                default:
                    return nil
                }
            },
            usage: try c.decodeIfPresent(Usage.self, forKey: .usage)
        )
    }
}
