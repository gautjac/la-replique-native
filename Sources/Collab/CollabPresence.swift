import Foundation
import SwiftUI
import FirebaseFirestore

/// Someone else who has this play open right now.
struct PresencePerson: Identifiable, Equatable {
    var id: String            // uid
    var name: String
    var colorHex: String
    /// The line their cursor is in, if any.
    var elementID: String?
    var lastSeen: Date
}

/// Who is here, and on which line. One small document per person
/// (`plays/{play}/presence/{uid}`), refreshed by a heartbeat; anyone silent for
/// 45 s is treated as gone, so a crashed app or a dead battery never leaves a
/// line locked.
@MainActor
final class PresenceChannel: ObservableObject {
    @Published private(set) var others: [PresencePerson] = []
    /// Fresh people per element id — what the editor's rows read.
    @Published private(set) var byElement: [String: [PresencePerson]] = [:]

    static let heartbeat: UInt64 = 20_000_000_000
    static let staleAfter: TimeInterval = 45

    private let playID: String?
    private var listener: ListenerRegistration?
    private var beat: Task<Void, Never>?
    private var raw: [PresencePerson] = []
    private var myName = ""
    private var myFocus: String?

    /// An inert channel, for plays that are not shared.
    static let none = PresenceChannel(playID: nil)

    init(playID: String?) { self.playID = playID }

    private var mine: DocumentReference? {
        guard let playID, let uid = CollabBackend.uid else { return nil }
        return CollabBackend.db.collection("plays").document(playID).collection("presence").document(uid)
    }

    static func color(for uid: String) -> String {
        let n = uid.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Theme.castSwatches[n % Theme.castSwatches.count]
    }

    func start(name: String) {
        guard let playID, listener == nil else { return }
        myName = name
        let me = CollabBackend.uid
        listener = CollabBackend.db.collection("plays").document(playID).collection("presence")
            .addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    guard let self, let snap else { return }
                    self.raw = snap.documents.compactMap { d in
                        guard d.documentID != me else { return nil }
                        let seen = (d.get("lastSeen", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date()
                        return PresencePerson(id: d.documentID, name: d["name"] as? String ?? "?",
                                              colorHex: d["color"] as? String ?? Self.color(for: d.documentID),
                                              elementID: d["elementID"] as? String, lastSeen: seen)
                    }
                    self.prune()
                }
            }
        write()
        beat = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                n += 1
                self?.prune()                                  // people go stale between snapshots
                if n % 4 == 0 { self?.write() }                // heartbeat every 20 s
            }
        }
    }

    func stop() {
        beat?.cancel(); beat = nil
        listener?.remove(); listener = nil
        mine?.delete()
        raw = []; prune()
    }

    /// The editor's cursor moved to another line (nil = nowhere).
    func setFocus(_ elementID: String?) {
        guard elementID != myFocus else { return }
        myFocus = elementID
        write()
    }

    private func write() {
        guard let mine, let uid = CollabBackend.uid else { return }
        var data: [String: Any] = ["uid": uid, "name": myName, "color": Self.color(for: uid), "lastSeen": FieldValue.serverTimestamp()]
        data["elementID"] = myFocus ?? FieldValue.delete()
        mine.setData(data, merge: true)
    }

    private func prune() {
        let fresh = raw.filter { Date().timeIntervalSince($0.lastSeen) < Self.staleAfter }.sorted { $0.name < $1.name }
        if fresh != others { others = fresh }
        let grouped = Dictionary(grouping: fresh.filter { $0.elementID != nil }, by: { $0.elementID! })
        if grouped != byElement { byElement = grouped }
    }
}

// MARK: - Members

struct CollabMember: Identifiable, Equatable {
    var id: String            // uid
    var name: String
    var role: String
}

@MainActor
final class MembersStore: ObservableObject {
    @Published private(set) var members: [CollabMember] = []
    private var listener: ListenerRegistration?
    private let playID: String

    init(playID: String) { self.playID = playID }

    private var collection: CollectionReference { CollabBackend.db.collection("plays").document(playID).collection("members") }

    func start() {
        guard listener == nil else { return }
        listener = collection.addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                self.members = snap.documents.map {
                    CollabMember(id: $0.documentID, name: $0["name"] as? String ?? "?", role: $0["role"] as? String ?? "reader")
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }
    func stop() { listener?.remove(); listener = nil }

    func setRole(_ role: String, for uid: String) async throws { try await collection.document(uid).updateData(["role": role]) }
    func remove(_ uid: String) async throws { try await collection.document(uid).delete() }
}
