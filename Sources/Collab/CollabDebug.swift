#if DEBUG
import Foundation
import SwiftData
import FirebaseAuth

/// DEBUG launch hooks for the two-device smoke test (see docs/COLLAB.md):
///   LR_COLLAB_AUTOSHARE=1      share the first solo play, log `COLLAB invite <code>`
///   LR_COLLAB_AUTOJOIN=<code>  join with that code
/// Both need LR_COLLAB_EMULATOR=1. They exist so the sync can be proven on two
/// simulators in one command instead of twenty taps.
@MainActor
enum CollabDebug {
    static func runLaunchHooks(_ context: ModelContext, open: (UUID) -> Void) async {
        let env = ProcessInfo.processInfo.environment
        guard CollabBackend.isAvailable else { return }
        // The emulator forgets its accounts on restart; a session left in the simulator's
        // keychain would then be refused with opaque stream errors. Start clean.
        if env["LR_COLLAB_AUTOSHARE"] == "1" || env["LR_COLLAB_AUTOJOIN"] != nil { try? Auth.auth().signOut() }
        do {
            if env["LR_COLLAB_AUTOSHARE"] == "1", let play = try context.fetch(FetchDescriptor<Play>()).first {
                let id = try await CollabService.share(play, from: context, as: "Simulateur A")
                guard let link = CollabStore.link(id) else { return }
                let invite = try await CollabService.invite(to: link, role: "writer")
                NSLog("[LaReplique] COLLAB invite %@", invite.token)
                open(id)
            } else if let code = env["LR_COLLAB_AUTOJOIN"], !code.isEmpty {
                let id = try await CollabService.join(code: code, as: "Simulateur B")
                NSLog("[LaReplique] COLLAB joined %@", id.uuidString)
                // LR_COLLAB_TWIN=1 recreates Jac's 2026-09-21 case: a second device of the
                // same iCloud account still holding the PRIVATE copy (same id) of a play
                // that was shared elsewhere.
                if env["LR_COLLAB_TWIN"] == "1", let shared = CollabStore.play(id) {
                    let twin = Play(title: shared.title + " (copie privée)", lang: shared.lang)
                    twin.id = id
                    context.insert(twin)
                    try? context.save()
                }
                open(id)
            }
        } catch {
            NSLog("[LaReplique] COLLAB hook failed: %@", error.localizedDescription)
        }
    }
}
#endif
