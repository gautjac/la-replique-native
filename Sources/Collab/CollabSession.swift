import Foundation
import SwiftData
import FirebaseFirestore

/// A shared play, live: the core + the transport + time. One per open shared play.
@MainActor
final class CollabSession: ObservableObject {
    enum Status: Equatable { case connecting, live, offline, gone }
    @Published private(set) var status: Status = .connecting

    let play: Play
    let link: CollabLink
    private let core: CollabCore
    private let transport: FirestoreTransport
    private var ticker: Task<Void, Never>?
    private var shadowDirty = false
    private var ticksSinceSave = 0

    /// How often local edits are gathered and sent. Short enough to feel live,
    /// long enough that a burst of typing is one write, not ten.
    static let tick: UInt64 = 400_000_000

    init(play: Play, link: CollabLink) {
        self.play = play
        self.link = link
        core = CollabCore(play: play, context: CollabStore.context, shadowData: link.shadow.isEmpty ? nil : link.shadow)
        transport = FirestoreTransport(playID: link.remoteID, known: core.shadow)
    }

    func start() {
        guard ticker == nil else { return }
        transport.onChanges = { [weak self] changes in
            guard let self else { return }
            self.send(self.core.applyRemote(changes))
            self.shadowDirty = true
        }
        transport.onLive = { [weak self] live in
            guard let self, self.status != .gone else { return }
            // Assign only on CHANGE: @Published fires even for an equal value, and
            // this runs on every snapshot — it used to re-run the whole page body
            // for each remote edit.
            let next: Status = live ? .live : .offline
            if self.status != next { self.status = next }
        }
        transport.onLost = { [weak self] in self?.status = .gone }
        transport.start()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tick)
                self?.tickOnce()
            }
        }
    }

    func stop() {
        ticker?.cancel(); ticker = nil
        tickOnce()
        transport.stop()
        saveShadow()
    }

    private func tickOnce() {
        guard status != .gone else { return }
        // Readers and commenters never push the script.
        if link.canWrite { send(core.flushLocal()) }
        ticksSinceSave += 1
        if shadowDirty, ticksSinceSave >= 8 { saveShadow() }
    }

    private func send(_ ops: [CollabOp]) {
        guard !ops.isEmpty, link.canWrite else { return }
        transport.send(ops)
        shadowDirty = true
    }

    private func saveShadow() {
        link.shadow = core.shadowData
        try? CollabStore.context.save()
        shadowDirty = false; ticksSinceSave = 0
    }
}

/// Sharing a play, inviting people, joining one.
@MainActor
enum CollabService {
    struct Invite: Equatable { var token: String; var role: String; var url: URL }
    static let inviteBase = "https://la-replique.netlify.app/rejoindre/"

    /// Turn a solo play into a shared one. The private original is removed ONLY
    /// after the server holds every line — a failed share leaves things as they were.
    static func share(_ play: Play, from source: ModelContext, as name: String) async throws -> UUID {
        guard CollabBackend.isAvailable else { throw CollabError.unavailable }
        let uid = try await CollabBackend.ensureSignedIn()
        let remoteID = play.id.uuidString
        let db = CollabBackend.db
        let playDoc = db.collection("plays").document(remoteID)

        let copy = CollabStore.copy(of: play, versionsFrom: source)
        let link = CollabLink(playID: copy.id, remoteID: remoteID, role: "writer", ownerUid: uid)
        CollabStore.context.insert(link)
        do {
            try await playDoc.setData(["ownerUid": uid, "createdAt": FieldValue.serverTimestamp()], merge: true)
            try await playDoc.collection("members").document(uid).setData(["uid": uid, "role": "writer", "name": name])
            let core = CollabCore(play: copy, context: CollabStore.context)
            let ops = core.flushLocal()
            for chunk in stride(from: 0, to: ops.count, by: 400).map({ Array(ops[$0..<min($0 + 400, ops.count)]) }) {
                let batch = db.batch()
                for case .put(let ref, let f) in chunk {
                    let d = ref.kind == .info ? playDoc : playDoc.collection(ref.kind == .character ? "characters" : "elements").document(ref.id)
                    batch.setData(f, forDocument: d, merge: ref.kind == .info)
                }
                try await batch.commit()
            }
            link.shadow = core.shadowData
            try CollabStore.context.save()
        } catch {
            CollabStore.remove(copy.id)
            throw CollabError.failed(error.localizedDescription)
        }
        source.delete(play)
        try? source.save()
        return copy.id
    }

    static func invite(to link: CollabLink, role: String, days: Int = 14) async throws -> Invite {
        let uid = try await CollabBackend.ensureSignedIn()
        let token = newToken()
        try await CollabBackend.db.collection("invites").document(token).setData([
            "playID": link.remoteID, "role": role, "createdBy": uid,
            "expiresAt": Timestamp(date: Date(timeIntervalSinceNow: Double(days) * 86_400)),
        ])
        return Invite(token: token, role: role, url: URL(string: inviteBase + token)!)
    }

    /// Accepts a bare code or a whole invitation link.
    static func join(code raw: String, as name: String) async throws -> UUID {
        guard CollabBackend.isAvailable else { throw CollabError.unavailable }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
        guard !token.isEmpty else { throw CollabError.badInvite }
        let uid = try await CollabBackend.ensureSignedIn()
        let db = CollabBackend.db
        let inv = try await db.collection("invites").document(token).getDocument(source: .server)
        guard inv.exists, let remoteID = inv["playID"] as? String, let role = inv["role"] as? String,
              let playID = UUID(uuidString: remoteID) else { throw CollabError.badInvite }
        if let exp = inv["expiresAt"] as? Timestamp, exp.dateValue() < Date() { throw CollabError.expiredInvite }
        if CollabStore.link(playID) != nil { return playID }            // already here

        let playDoc = db.collection("plays").document(remoteID)
        let seat = playDoc.collection("members").document(uid)
        do {
            if try await !seat.getDocument(source: .server).exists {
                try await seat.setData(["uid": uid, "role": role, "name": name, "via": token])
            }
        } catch {
            try await seat.setData(["uid": uid, "role": role, "name": name, "via": token])
        }
        let owner = (try await playDoc.getDocument(source: .server))["ownerUid"] as? String ?? ""
        let all = try await FirestoreTransport(playID: remoteID, known: [:]).fetchAll()

        let play = Play(title: "", lang: .fr)
        play.id = playID
        CollabStore.context.insert(play)
        let core = CollabCore(play: play, context: CollabStore.context)
        core.adopt(all)
        let link = CollabLink(playID: playID, remoteID: remoteID, role: role, ownerUid: owner)
        link.shadow = core.shadowData
        CollabStore.context.insert(link)
        try CollabStore.context.save()
        return playID
    }

    /// Ten characters, no look-alikes — short enough to read out over the phone.
    static func newToken() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<10).map { _ in alphabet.randomElement()! })
    }
}
