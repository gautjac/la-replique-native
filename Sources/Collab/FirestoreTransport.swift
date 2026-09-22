import Foundation
import FirebaseFirestore

/// The road between `CollabCore` and Firestore for ONE shared play.
///
/// It honours the core's transport contract for free: Firestore listeners report
/// server state overlaid with this device's own pending writes, in order.
@MainActor
final class FirestoreTransport {
    let playID: String
    var onChanges: ([RemoteChange]) -> Void = { _ in }
    /// true once every listener has heard from the SERVER (not just the cache).
    var onLive: (Bool) -> Void = { _ in }
    var onLost: () -> Void = {}
    /// Attribution of lines, as it changes: element id → who last touched it (nil = line gone).
    var onEdits: ([String: LineEdit?]) -> Void = { _ in }
    /// Who I am, for the lines I write.
    var author: (uid: String, name: String)?

    private let db = CollabBackend.db
    private var listeners: [ListenerRegistration] = []
    private var fromServer: Set<EntityKind> = []
    /// What the core's shadow held when we started — used once, on the first
    /// server snapshot, to notice what was deleted while this device was away.
    private var known: [EntityKind: Set<String>]

    static let infoKeys: Set<String> = [CollabField.title, CollabField.subtitle, CollabField.author,
                                        CollabField.logline, CollabField.lang, CollabField.altLang]

    init(playID: String, known: [EntityRef: Fields]) {
        self.playID = playID
        self.known = Dictionary(grouping: known.keys, by: \.kind).mapValues { Set($0.map(\.id)) }
    }

    private var playDoc: DocumentReference { db.collection("plays").document(playID) }
    private func collection(_ kind: EntityKind) -> CollectionReference {
        playDoc.collection(kind == .character ? "characters" : "elements")
    }
    private func doc(_ ref: EntityRef) -> DocumentReference {
        ref.kind == .info ? playDoc : collection(ref.kind).document(ref.id)
    }

    private static func fields(_ data: [String: Any], only keys: Set<String>? = nil) -> Fields {
        var out: Fields = [:]
        // `_`-prefixed keys are META (attribution), never script content.
        for (k, v) in data where !k.hasPrefix("_") { if let s = v as? String, keys?.contains(k) ?? true { out[k] = s } }
        return out
    }

    private func stamped(_ data: [String: Any], _ ref: EntityRef) -> [String: Any] {
        guard ref.kind == .element, let author else { return data }
        var d = data
        d["_by"] = author.uid; d["_byName"] = author.name; d["_at"] = FieldValue.serverTimestamp()
        return d
    }

    // MARK: listening

    func start() {
        stop()
        listeners.append(playDoc.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let snap, error == nil else { self.onLost(); return }
                if !snap.exists {
                    if !snap.metadata.isFromCache { self.onLost() }
                    return
                }
                self.onChanges([.upsert(.info, Self.fields(snap.data() ?? [:], only: Self.infoKeys))])
                self.heard(.info, fromCache: snap.metadata.isFromCache)
            }
        })
        for kind in [EntityKind.character, .element] {
            listeners.append(collection(kind).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self, let snap, error == nil else { self?.onLost(); return }
                    var changes: [RemoteChange] = snap.documentChanges.map { ch in
                        let ref = EntityRef(kind: kind, id: ch.document.documentID)
                        return ch.type == .removed ? .removed(ref) : .upsert(ref, Self.fields(ch.document.data()))
                    }
                    // First word from the server: anything we knew that it no longer
                    // has was deleted while we were away. (A cache snapshot can't tell.)
                    if !snap.metadata.isFromCache, let mine = self.known.removeValue(forKey: kind) {
                        let alive = Set(snap.documents.map(\.documentID))
                        changes += mine.subtracting(alive).map { .removed(EntityRef(kind: kind, id: $0)) }
                    }
                    if !changes.isEmpty { self.onChanges(changes) }
                    if kind == .element {
                        var edits: [String: LineEdit?] = [:]
                        for ch in snap.documentChanges {
                            let d = ch.document
                            if ch.type == .removed { edits[d.documentID] = .some(nil); continue }
                            guard let uid = d["_by"] as? String else { continue }
                            let at = (d.get("_at", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date()
                            edits[d.documentID] = LineEdit(uid: uid, name: d["_byName"] as? String ?? "?", at: at)
                        }
                        if !edits.isEmpty { self.onEdits(edits) }
                    }
                    self.heard(kind, fromCache: snap.metadata.isFromCache)
                }
            })
        }
    }

    private func heard(_ kind: EntityKind, fromCache: Bool) {
        if fromCache { fromServer.remove(kind) } else { fromServer.insert(kind) }
        onLive(fromServer.count == EntityKind.allCases.count)
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        fromServer = []
    }

    // MARK: sending

    /// Creations and deletions travel in batches. Patches go ONE BY ONE on purpose:
    /// a patch to a line someone just deleted must fail alone (delete beats edit) —
    /// inside a batch it would take every other write down with it.
    func send(_ ops: [CollabOp]) {
        var batch = db.batch()
        var count = 0
        func commitIfFull(force: Bool = false) {
            guard count > 0, force || count >= 400 else { return }
            batch.commit { error in if let error { NSLog("[LaReplique] collab batch failed: %@", error.localizedDescription) } }
            batch = db.batch(); count = 0
        }
        for op in ops {
            switch op {
            case .put(let ref, let f):
                // The play document also carries ownerUid — merge, never replace.
                batch.setData(stamped(f, ref), forDocument: doc(ref), merge: ref.kind == .info)
                count += 1
            case .delete(let ref):
                batch.deleteDocument(doc(ref)); count += 1
            case .patch(let ref, let set, let unset):
                commitIfFull(force: true)             // keep the writes in order
                var data: [String: Any] = stamped(set, ref)
                for k in unset { data[k] = FieldValue.delete() }
                doc(ref).updateData(data) { error in
                    // NOT_FOUND = the line is gone; the listener will tell the core.
                    if let e = error as NSError?, e.code != FirestoreErrorCode.notFound.rawValue {
                        NSLog("[LaReplique] collab patch failed: %@", e.localizedDescription)
                    }
                }
            }
            commitIfFull()
        }
        commitIfFull(force: true)
    }

    /// The whole shared play, from the server — for joining.
    func fetchAll() async throws -> [EntityRef: Fields] {
        let info = try await playDoc.getDocument(source: .server)
        guard info.exists else { throw CollabError.notFound }
        var all: [EntityRef: Fields] = [.info: Self.fields(info.data() ?? [:], only: Self.infoKeys)]
        for kind in [EntityKind.character, .element] {
            for d in try await collection(kind).getDocuments(source: .server).documents {
                all[EntityRef(kind: kind, id: d.documentID)] = Self.fields(d.data())
            }
        }
        return all
    }
}
