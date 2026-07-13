import Foundation
import ClaudeKit

/// Bring-your-own-key storage. Both keys live in the Keychain (via ClaudeKit's
/// `KeychainStore`) — never in the bundle, never on a server.
enum AppKeys {
    private static let service = "app.atelier.lareplique"

    static let anthropic = KeychainStore(service: service, account: "anthropic.apiKey")
    static let elevenLabs = KeychainStore(service: service, account: "elevenlabs.apiKey")

    static var hasAnthropic: Bool { anthropic.hasValue }
    static var hasElevenLabs: Bool { elevenLabs.hasValue }
}
