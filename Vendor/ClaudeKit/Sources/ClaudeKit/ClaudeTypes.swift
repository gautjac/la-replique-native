import Foundation

// MARK: - Content blocks

/// An image attachment for vision requests, sent as a base64 content block.
public struct ClaudeImage: Sendable, Equatable {
    /// The image encodings the Messages API accepts from this kit.
    public enum MediaType: String, Sendable, Codable {
        case jpeg = "image/jpeg"
        case png = "image/png"
    }

    /// Raw encoded image bytes (already JPEG/PNG — the kit does not transcode).
    public var data: Data
    /// Which encoding `data` holds.
    public var mediaType: MediaType

    public init(data: Data, mediaType: MediaType) {
        self.data = data
        self.mediaType = mediaType
    }

    /// A JPEG image block.
    public static func jpeg(_ data: Data) -> ClaudeImage { ClaudeImage(data: data, mediaType: .jpeg) }
    /// A PNG image block.
    public static func png(_ data: Data) -> ClaudeImage { ClaudeImage(data: data, mediaType: .png) }
}

/// One content block inside a message: plain text or an image.
public enum ClaudeContent: Sendable, Equatable {
    case text(String)
    case image(ClaudeImage)
}

extension ClaudeContent: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, source }
    private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let image):
            try c.encode("image", forKey: .type)
            var s = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try s.encode("base64", forKey: .type)
            try s.encode(image.mediaType, forKey: .mediaType)
            try s.encode(image.data.base64EncodedString(), forKey: .data)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "image":
            let s = try c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            let mediaType = try s.decode(ClaudeImage.MediaType.self, forKey: .mediaType)
            let base64 = try s.decode(String.self, forKey: .data)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: s, debugDescription: "invalid base64")
            }
            self = .image(ClaudeImage(data: data, mediaType: mediaType))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown content type \(type)")
        }
    }
}

// MARK: - Messages

/// One turn of a conversation.
public struct ClaudeMessage: Sendable, Equatable, Codable {
    /// Who speaks this turn.
    public enum Role: String, Sendable, Codable {
        case user, assistant
    }

    public var role: Role
    public var content: [ClaudeContent]

    public init(role: Role, content: [ClaudeContent]) {
        self.role = role
        self.content = content
    }

    /// A plain-text user turn.
    public static func user(_ text: String) -> ClaudeMessage {
        ClaudeMessage(role: .user, content: [.text(text)])
    }

    /// A user turn made of arbitrary blocks (e.g. an image plus a question).
    public static func user(_ blocks: [ClaudeContent]) -> ClaudeMessage {
        ClaudeMessage(role: .user, content: blocks)
    }

    /// A plain-text assistant turn (for replaying multi-turn history).
    public static func assistant(_ text: String) -> ClaudeMessage {
        ClaudeMessage(role: .assistant, content: [.text(text)])
    }
}

// MARK: - Tools

/// A tool definition — used for structured/JSON output by forcing the model to
/// "call" a tool whose `input_schema` is the shape you want back.
public struct ClaudeTool: Sendable, Equatable, Codable {
    public var name: String
    public var description: String
    /// A JSON Schema, expressible as a Swift literal (see ``JSONValue``).
    public var inputSchema: JSONValue

    private enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// How the model may use the request's tools.
public enum ClaudeToolChoice: Sendable, Equatable {
    /// The model decides whether to use a tool.
    case auto
    /// The model may pick any tool but must use one.
    case any
    /// Force one specific tool — the guaranteed-structured-output pattern.
    case tool(String)
}

extension ClaudeToolChoice: Encodable {
    private enum CodingKeys: String, CodingKey { case type, name }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try c.encode("auto", forKey: .type)
        case .any:
            try c.encode("any", forKey: .type)
        case .tool(let name):
            try c.encode("tool", forKey: .type)
            try c.encode(name, forKey: .name)
        }
    }
}

// MARK: - Request

/// Everything one Messages API call needs. Build it, hand it to
/// ``ClaudeClient/send(_:)`` or ``ClaudeClient/stream(_:)``.
public struct ClaudeRequest: Sendable, Equatable {
    public var model: ClaudeModel
    /// Upper bound on generated tokens.
    public var maxTokens: Int
    /// Optional system prompt.
    public var system: String?
    /// The conversation so far; must end on a `user` turn.
    public var messages: [ClaudeMessage]
    /// Sampling temperature 0...1. Leave nil for the model default (some
    /// models — opus, fable — reject an explicit temperature).
    public var temperature: Double?
    /// Tool definitions, for structured output.
    public var tools: [ClaudeTool]?
    /// Tool-choice constraint; pair `.tool(name)` with a single tool for
    /// guaranteed-JSON responses.
    public var toolChoice: ClaudeToolChoice?

    public init(
        model: ClaudeModel = .sonnet,
        maxTokens: Int = 4096,
        system: String? = nil,
        messages: [ClaudeMessage],
        temperature: Double? = nil,
        tools: [ClaudeTool]? = nil,
        toolChoice: ClaudeToolChoice? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.temperature = temperature
        self.tools = tools
        self.toolChoice = toolChoice
    }
}
