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
        for (k, v) in data { if let s = v as? String, keys?.contains(k) ?? true { out[k] = s } }
        return out
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
                batch.setData(f, forDocument: doc(ref), merge: ref.kind == .info)
                count += 1
            case .delete(let ref):
                batch.deleteDocument(doc(ref)); count += 1
            case .patch(let ref, let set, let unset):
                commitIfFull(force: true)             // keep the writes in order
                var data: [String: Any] = set
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
