import Foundation
import FirebaseFirestore

// The history log of a shared play: who changed what, when, and what it said
// before. `plays/{play}/history/{id}`, written by the writer's own device as it
// syncs; a burst of typing on one line by one person is ONE entry (its `after`
// keeps moving for ten minutes), so the log reads like a diary, not a keystroke
// dump. Entries are never deleted.

struct HistoryEntry: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case edit, add, delete, move, cast, info }
    var id: String
    var uid: String
    var name: String
    var kind: Kind
    /// Element id, "info" for the play's title/author…, or a character id for cast changes.
    var elementID: String
    /// The speaker's name at the time, for cues.
    var speaker: String?
    var before: Fields?
    var after: Fields?
    var at: Date
    var count: Int

    var isLine: Bool { kind != .cast && kind != .info }
    /// The line's text, before and after (label for headings).
    var textBefore: String? { before?["text"] ?? before?["label"] }
    var textAfter: String? { after?["text"] ?? after?["label"] }
}

/// Turns the ops a device sends into history entries, coalescing bursts.
@MainActor
final class HistoryLog {
    private let playID: String
    private let author: (uid: String, name: String)
    private let play: Play
    /// Open (extendable) entries per element: doc id + when it was last extended.
    private var open: [String: (id: String, at: Date)] = [:]
    static let window: TimeInterval = 600

    init(playID: String, author: (uid: String, name: String), play: Play) {
        self.playID = playID; self.author = author; self.play = play
    }

    private var collection: CollectionReference { CollabBackend.db.collection("plays").document(playID).collection("history") }

    /// `old` is the core's shadow BEFORE the flush that produced `ops`.
    func record(_ ops: [CollabOp], old: [EntityRef: Fields]) {
        for op in ops {
            switch op {
            case .put(let ref, let f):
                write(kind: ref.kind == .character ? .cast : ref.kind == .info ? .info : .add, ref: ref, before: nil, after: f)
            case .delete(let ref):
                write(kind: ref.kind == .character ? .cast : .delete, ref: ref, before: old[ref], after: nil)
            case .patch(let ref, let set, let unset):
                let was = old[ref] ?? [:]
                var before: Fields = [:], after: Fields = [:]
                for (k, v) in set { before[k] = was[k]; after[k] = v }
                for k in unset { before[k] = was[k] }
                let onlyOrder = set.keys.allSatisfy { $0 == CollabField.orderKey } && unset.isEmpty
                let kind: HistoryEntry.Kind = ref.kind == .character ? .cast : ref.kind == .info ? .info : onlyOrder ? .move : .edit
                if kind == .edit, set.count == 1, set.keys.first == CollabField.orderKey { continue }
                // Keep the whole "before" text so a restore has something to restore.
                if kind == .edit { for k in ["text", "label"] where before[k] == nil { if let v = was[k] { before[k] = v } } }
                write(kind: kind, ref: ref, before: before, after: after)
            }
        }
    }

    private func write(kind: HistoryEntry.Kind, ref: EntityRef, before: Fields?, after: Fields?) {
        let key = ref.id
        let now = Date()
        // Extend a still-open entry of the same kind on the same line.
        if kind == .edit, let o = open[key], now.timeIntervalSince(o.at) < Self.window {
            open[key] = (o.id, now)
            var patch: [String: Any] = ["at": FieldValue.serverTimestamp(), "count": FieldValue.increment(Int64(1))]
            if let after { patch["after"] = after }
            collection.document(o.id).updateData(patch)
            return
        }
        let id = UUID().uuidString
        var data: [String: Any] = ["uid": author.uid, "name": author.name, "kind": kind.rawValue, "elementID": key,
                                   "at": FieldValue.serverTimestamp(), "count": 1]
        if let before { data["before"] = before }
        if let after { data["after"] = after }
        if ref.kind == .element {
            // The speaker, from the line itself (a text edit's patch carries no characterID).
            let cid = after?[CollabField.characterID] ?? before?[CollabField.characterID]
                ?? (play.elements ?? []).first { $0.id.uuidString == key }?.characterID
            if let cid, let who = play.character(id: cid)?.name { data["speaker"] = who }
        }
        collection.document(id).setData(data)
        if kind == .edit { open[key] = (id, now) } else { open[key] = nil }
    }
}

/// The log, live, newest first.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private var listener: ListenerRegistration?
    private let playID: String
    init(playID: String) { self.playID = playID }

    func start() {
        guard listener == nil else { return }
        listener = CollabBackend.db.collection("plays").document(playID).collection("history")
            .order(by: "at", descending: true).limit(to: 500)
            .addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    guard let self, let snap else { return }
                    self.entries = snap.documents.compactMap { d in
                        guard let kind = HistoryEntry.Kind(rawValue: d["kind"] as? String ?? "") else { return nil }
                        let f = { (k: String) -> Fields? in (d[k] as? [String: Any])?.compactMapValues { $0 as? String } }
                        let at = (d.get("at", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date()
                        return HistoryEntry(id: d.documentID, uid: d["uid"] as? String ?? "", name: d["name"] as? String ?? "?",
                                            kind: kind, elementID: d["elementID"] as? String ?? "", speaker: d["speaker"] as? String,
                                            before: f("before"), after: f("after"), at: at, count: d["count"] as? Int ?? 1)
                    }
                }
            }
    }
    func stop() { listener?.remove(); listener = nil }
}

// MARK: - Named versions of a shared play

struct SharedVersion: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var uid: String
    var by: String
    var at: Date
    var json: String
    /// Who last touched each line when the snapshot was taken (element id → name).
    var authors: [String: String]
}

@MainActor
final class SharedVersionsStore: ObservableObject {
    @Published private(set) var versions: [SharedVersion] = []
    private var listener: ListenerRegistration?
    private let playID: String
    init(playID: String) { self.playID = playID }
    private var collection: CollectionReference { CollabBackend.db.collection("plays").document(playID).collection("versions") }

    func start() {
        guard listener == nil else { return }
        listener = collection.order(by: "at", descending: true).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                self.versions = snap.documents.map { d in
                    SharedVersion(id: d.documentID, name: d["name"] as? String ?? "", uid: d["uid"] as? String ?? "",
                                  by: d["by"] as? String ?? "?", at: (d.get("at", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date(),
                                  json: d["json"] as? String ?? "{}", authors: (d["authors"] as? [String: String]) ?? [:])
                }
            }
        }
    }
    func stop() { listener?.remove(); listener = nil }

    func save(_ play: Play, name: String, by: (uid: String, name: String), authors: [String: String]) async throws {
        let data = try PlayFormat.aiJSON(from: play, withElementIDs: true)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await collection.document(UUID().uuidString).setData([
            "name": name.isEmpty ? String(localized: "Version") : name, "uid": by.uid, "by": by.name,
            "at": FieldValue.serverTimestamp(), "json": json, "authors": authors,
        ])
    }
    func remove(_ v: SharedVersion) async throws { try await collection.document(v.id).delete() }

    static func doc(_ v: SharedVersion) -> PlayDoc? { try? PlayFormat.decode(Data(v.json.utf8)) }
}
