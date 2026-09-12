import Foundation
import SwiftData

/// One shared store, CloudKit-synced. The schema is CloudKit-compatible — all
/// properties are defaulted/optional and there are no unique constraints — so
/// `cloudKitDatabase: .automatic` mirrors plays across the user's devices via
/// their private iCloud database. Falls back to a local, then in-memory store if
/// iCloud/CloudKit is unavailable, so the app always opens.
enum Persistence {
    enum Tier: String { case cloudKit, local, memory }
    @MainActor private(set) static var tier: Tier = .memory

    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema([Play.self, Character.self, Element.self, Version.self])

        // Under XCTest / SwiftUI previews, skip CloudKit — the mirroring delegate
        // is unstable in those hosts and would destabilize the process.
        let env = ProcessInfo.processInfo.environment
        var ephemeral = env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #if DEBUG
        // `LR_EPHEMERAL=1` — a throwaway in-memory store for driving a Debug build
        // on a developer Mac WITHOUT opening (or syncing) the real library.
        if env["LR_EPHEMERAL"] == "1" { ephemeral = true }
        #endif
        if ephemeral {
            tier = .memory
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }

        #if DEBUG
        // `LR_SCHEMA_PRIME=1` — schema-priming run (see tools/prime-schema.sh).
        //
        // Production CloudKit can't create record types, so every type must be
        // materialised in DEVELOPMENT and deployed. But a type only appears once a
        // record of it is saved — which is how `CD_Version` came to exist in
        // neither environment, leaving the first saved version silently unsyncable.
        //
        // This opens a THROWAWAY store so a Development-CloudKit run can mint the
        // missing types without touching the real library or its mirroring
        // metadata (pointing a dev build at the production store would reset that
        // metadata and risk re-uploading everything as duplicates).
        if env["LR_SCHEMA_PRIME"] == "1" {
            let url = URL.temporaryDirectory.appending(path: "lr-schema-prime-\(env["LR_PRIME_TAG"] ?? "0").store")
            let cfg = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .automatic)
            let container = try! ModelContainer(for: schema, configurations: [cfg])
            tier = .cloudKit
            NSLog("[LaReplique] SCHEMA PRIME store: %@", url.path)
            return container
        }
        #endif

        // Tier 1 — CloudKit-synced (the goal).
        do {
            let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [cfg])
            tier = .cloudKit
            NSLog("[LaReplique] store tier: CloudKit ✓")
            return container
        } catch {
            NSLog("[LaReplique] CloudKit store failed → %@", String(describing: error))
        }

        // Tier 2 — explicit local, CloudKit disabled, so it always persists.
        do {
            let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [cfg])
            tier = .local
            NSLog("[LaReplique] store tier: local (no sync)")
            return container
        } catch {
            NSLog("[LaReplique] local store failed → %@", String(describing: error))
        }

        // Tier 3 — last resort: in-memory (no persistence).
        tier = .memory
        NSLog("[LaReplique] store tier: IN-MEMORY (no persistence!)")
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }()
}

#if DEBUG
extension Persistence {
    /// Writes one row of EVERY model so CloudKit mints the full record-type set in
    /// the Development environment (a type only exists once a record of it is
    /// saved). Deploy Development → Production afterwards. No-op unless
    /// LR_SCHEMA_PRIME=1, which also forces a throwaway store.
    @MainActor
    static func primeSchemaIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["LR_SCHEMA_PRIME"] == "1" else { return }
        let play = Play(title: "Schema prime")
        context.insert(play)
        let character = Character(name: "PRIME", colorHex: "#4f7cff", order: 0)
        character.play = play
        context.insert(character)
        let element = Element(kind: .cue, order: 0)
        element.play = play
        element.text = "prime"
        context.insert(element)
        context.insert(Version(playID: play.id, name: "prime", json: "{}"))
        do {
            try context.save()
            NSLog("[LaReplique] SCHEMA PRIME: saved one row of Play/Character/Element/Version — waiting for CloudKit export…")
        } catch {
            NSLog("[LaReplique] SCHEMA PRIME failed: %@", String(describing: error))
        }
    }
}
#endif
