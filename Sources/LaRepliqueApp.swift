import SwiftUI
import SwiftData

/// La Réplique — a bilingual playwriting studio for the stage.
/// One multiplatform target → a single universal app, native on iPhone, iPad and Mac.
@main
struct LaRepliqueApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.gel)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Persistence.shared)
        #if os(macOS)
        .defaultSize(width: 1280, height: 840)
        #endif
    }
}
