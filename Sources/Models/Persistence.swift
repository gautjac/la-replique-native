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
        if env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            tier = .memory
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }

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
