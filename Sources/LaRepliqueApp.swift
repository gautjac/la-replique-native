import SwiftUI
import SwiftData

/// La Réplique — a bilingual playwriting studio for the stage.
/// One multiplatform target → a single universal app, native on iPhone, iPad and Mac.
@main
struct LaRepliqueApp: App {
    @StateObject private var loc = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, loc.language.locale)
                .id(loc.language)          // re-render the whole tree when the language switches
                .tint(Theme.gel)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Persistence.shared)
        #if os(macOS)
        .defaultSize(width: 1280, height: 840)
        #endif

        #if os(macOS)
        // BYOK keys + interface language live in the standard Settings window (⌘,) on the Mac.
        Settings {
            KeySettingsView()
                .environment(\.locale, loc.language.locale)
                .id(loc.language)
        }
        #endif
    }
}
