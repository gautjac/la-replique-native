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
}
