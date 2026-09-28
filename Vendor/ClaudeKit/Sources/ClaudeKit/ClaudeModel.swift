import Foundation

/// The Claude model to run a request against.
///
/// The four named cases carry the atelier's current pinned model ids so every
/// app upgrades in one place; `.custom` escapes the hatch for anything else
/// (dated snapshots, betas, aliases).
public enum ClaudeModel: Sendable, Hashable {
    /// Deep-reasoning flagship — `claude-opus-4-8`.
    case opus
    /// The daily driver — `claude-sonnet-5`.
    case sonnet
    /// Fast and cheap — `claude-haiku-4-5-20251001`.
    case haiku
    /// The adaptive-effort model — `claude-fable-5`.
    case fable
    /// Any model id verbatim, e.g. `"claude-sonnet-4-5"`.
    case custom(String)

    /// The model id string sent to the API.
    public var id: String {
        switch self {
        case .opus:            return "claude-opus-4-8"
        case .sonnet:          return "claude-sonnet-5"
        case .haiku:           return "claude-haiku-4-5-20251001"
        case .fable:           return "claude-fable-5"
        case .custom(let id):  return id
        }
    }

    /// The shortest prefix (in tokens) this model will cache; anything shorter
    /// silently isn't (`cache_creation_input_tokens` stays 0). Nil for an id
    /// the kit doesn't know — check the model's docs.
    public var minimumCacheablePrefixTokens: Int? {
        let id = self.id
        if id.hasPrefix("claude-opus-5") || id.hasPrefix("claude-fable-5") { return 512 }
        if id.hasPrefix("claude-opus-4-7") { return 2048 }
        if id.hasPrefix("claude-haiku-4-5") || id.hasPrefix("claude-opus-4-6") || id.hasPrefix("claude-opus-4-5") { return 4096 }
        if id.hasPrefix("claude-opus-4-8") || id.hasPrefix("claude-sonnet-5") || id.hasPrefix("claude-sonnet-4")
            || id.hasPrefix("claude-opus-4-1") || id.hasPrefix("claude-opus-4-2") { return 1024 } // …-4-2025… = dated Opus 4
        return nil
    }
}
