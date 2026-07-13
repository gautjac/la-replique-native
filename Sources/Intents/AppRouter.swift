import Foundation
import Combine

/// A tiny in-process router so App Intents (Siri / Shortcuts / Spotlight) can ask
/// the running app to open a specific play. Intents run in-app (there is no
/// separate AppIntents extension), so a shared observable is enough.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    private init() {}

    /// Set by an intent; observed by `RootView`, which selects the play then clears it.
    @Published var openPlayID: UUID?
}
