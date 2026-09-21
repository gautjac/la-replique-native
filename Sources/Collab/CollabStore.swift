import Foundation
import SwiftData

/// What ties a local shared play to its copy on the server.
@Model
final class CollabLink {
    /// The local `Play.id` — and, as a string, the server document id.
    var playID: UUID = UUID()
    var remoteID: String = ""
    var role: String = "writer"
    var ownerUid: String = ""
    /// `CollabCore.shadowData` — the last state both sides agreed on.
    var shadow: Data = Data()
    var joinedAt: Date = Date()
    /// The name this person gave when sharing or joining — what others see.
    var myName: String = ""

    init(playID: UUID, remoteID: String, role: String, ownerUid: String) {
        self.playID = playID; self.remoteID = remoteID; self.role = role; self.ownerUid = ownerUid
    }

    var canWrite: Bool { role == "writer" }
}

/// Shared plays live in their OWN local store — same model classes, second
/// container, never mirrored to iCloud. If a shared play also rode the private
/// CloudKit sync, it would reach the owner's other devices by two roads, and a
/// stale iCloud copy could overwrite a newer line and push that regression to
/// every collaborator. One road only: Firestore.
@MainActor
enum CollabStore {
    static let container: ModelContainer = {
        let schema = Schema([Play.self, Character.self, Element.self, Version.self, CollabLink.self])
        let env = ProcessInfo.processInfo.environment
        let memory = env["XCTestConfigurationFilePath"] != nil || env["LR_EPHEMERAL"] == "1"
        if !memory {
            let url = URL.applicationSupportDirectory.appending(path: "shared-plays.store")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cfg = ModelConfiguration("shared-plays", schema: schema, url: url, cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: schema, configurations: [cfg]) { return c }
        }
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration("shared-plays", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }()

    static var context: ModelContext { container.mainContext }

    static func play(_ id: UUID) -> Play? {
        var d = FetchDescriptor<Play>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Ids of every play shared on this device.
    static func sharedIDs() -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<CollabLink>())) ?? []).map(\.playID))
    }

    static func link(_ playID: UUID) -> CollabLink? {
        var d = FetchDescriptor<CollabLink>(predicate: #Predicate { $0.playID == playID }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// A copy of a solo play in this store, with the SAME ids for the play, its
    /// characters and its elements — notes and speakers stay attached. The
    /// original is left alone; the caller removes it only once the share succeeded.
    static func copy(of play: Play, versionsFrom source: ModelContext) -> Play {
        let p = Play(title: play.title, lang: play.lang)
        p.id = play.id
        p.subtitle = play.subtitle; p.author = play.author; p.logline = play.logline
        p.notes = play.notes; p.premiere = play.premiere; p.altLangRaw = play.altLangRaw
        p.createdAt = play.createdAt; p.updatedAt = play.updatedAt; p.publicShareID = play.publicShareID
        context.insert(p)
        for c in play.characters ?? [] {
            let n = Character(name: c.name, colorHex: c.colorHex, order: c.order)
            n.id = c.id; n.note = c.note; n.voiceID = c.voiceID; n.play = p
            context.insert(n)
        }
        for e in play.elements ?? [] {
            let n = Element(kind: e.kind, order: e.order)
            n.id = e.id; n.characterID = e.characterID; n.text = e.text; n.label = e.label
            n.setting = e.setting; n.synopsis = e.synopsis; n.beatRaw = e.beatRaw
            n.parenthetical = e.parenthetical; n.alt = e.alt; n.play = p
            context.insert(n)
        }
        let pid = play.id
        for v in (try? source.fetch(FetchDescriptor<Version>(predicate: #Predicate { $0.playID == pid }))) ?? [] {
            let n = Version(playID: v.playID, name: v.name, json: v.json); n.createdAt = v.createdAt
            context.insert(n)
        }
        return p
    }

    static func remove(_ playID: UUID) {
        if let p = play(playID) { context.delete(p) }
        if let l = link(playID) { context.delete(l) }
        try? context.save()
    }
}
