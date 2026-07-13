import Foundation

/// Typed failures from ``ClaudeClient``, mapped from HTTP status codes, the
/// API's error envelope, and transport-level problems.
public enum ClaudeError: Error, Sendable, Equatable {
    /// No API key was available (empty string passed, or Keychain empty).
    case missingAPIKey
    /// 401/403 — the key is wrong, revoked, or not authorized.
    case invalidAPIKey(message: String)
    /// 429 — rate limited. `retryAfter` is the server's `retry-after` header
    /// in seconds, when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// 529 (or an in-stream `overloaded_error`) — Anthropic is overloaded;
    /// retry with backoff.
    case overloaded
    /// Any other non-2xx status, with the server's error message.
    case http(status: Int, message: String)
    /// The transport failed (no network, timeout, cancelled...).
    case network(String)
    /// The response arrived but could not be decoded / had no usable content.
    case decoding(String)
    /// The API reported an error inside an event stream.
    case server(type: String, message: String)
}

extension ClaudeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key configured."
        case .invalidAPIKey(let message):
            return "Invalid Anthropic API key: \(message)"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited — retry in \(Int(retryAfter.rounded())) s."
            }
            return "Rate limited — retry shortly."
        case .overloaded:
            return "Anthropic is overloaded — retry with backoff."
        case .http(let status, let message):
            return "Anthropic HTTP \(status): \(message)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .decoding(let detail):
            return "Could not read the response: \(detail)"
        case .server(let type, let message):
            return "Anthropic error (\(type)): \(message)"
        }
    }
}
