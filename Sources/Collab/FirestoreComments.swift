import Foundation
import FirebaseFirestore

/// Notes on a SHARED play: `plays/{play}/notes/{id}`, live.
///
/// Same rules of the game as everywhere else (`Comments.swift`), simpler storage
/// than the CloudKit reading: here the server's rules let a writer resolve or hide
/// anyone's note directly, so there are no owner-side lists — `resolved` and
/// `hidden` are plain fields on the note. Anyone with the Écrire or Commenter
/// role leaves notes, signed with whichever account they came in with.
struct FirestoreComments: CommentBackend {
    let playID: String
    let role: String
    let ownerUid: String

    @MainActor private var notes: CollectionReference {
        CollabBackend.db.collection("plays").document(playID).collection("notes")
    }

    func me() async throws -> String {
        guard let uid = await CollabBackend.uid else { throw NotesError.notSignedIn }
        return uid
    }

    func meta(shareID: String) async throws -> NotesMeta? {
        NotesMeta(commentsOpen: true, resolved: [], hidden: [], owner: ownerUid, viewerCanModerate: role == "writer")
    }

    @MainActor
    func list(shareID: String) async throws -> [PlayComment] {
        try await notes.getDocuments().documents.compactMap(Self.comment)
    }

    @MainActor
    func post(_ d: CommentDraft) async throws -> PlayComment {
        guard let uid = CollabBackend.uid else { throw NotesError.notSignedIn }
        var data: [String: Any] = ["authorUid": uid, "authorName": d.authorName, "elementID": d.elementID, "body": d.body,
                                   "resolved": false, "hidden": false, "createdAt": FieldValue.serverTimestamp()]
        if let q = d.quote, !q.isEmpty { data["quote"] = q }
        if let p = d.parentID, !p.isEmpty { data["parentID"] = p }
        let ref = notes.document(UUID().uuidString)
        try await ref.setData(data)
        return PlayComment(id: ref.documentID, shareID: playID, elementID: d.elementID, quote: d.quote, body: d.body,
                           authorName: d.authorName, parentID: d.parentID, resolved: false, createdAt: Date(), creator: uid)
    }

    @MainActor func remove(id: String) async throws { try await notes.document(id).delete() }

    /// Author or writer — the server's rules decide; the field is the same.
    @MainActor func setResolvedByAuthor(id: String, resolved: Bool) async throws {
        try await notes.document(id).updateData(["resolved": resolved])
    }

    @MainActor func moderate(id: String, resolved: Bool?, hidden: Bool?) async throws {
        var data: [String: Any] = [:]
        if let resolved { data["resolved"] = resolved }
        if let hidden { data["hidden"] = hidden }
        if !data.isEmpty { try await notes.document(id).updateData(data) }
    }

    func ownerUpdate(shareID: String, commentsOpen: Bool?, resolved: [String]?, hidden: [String]?) async throws -> NotesMeta {
        try await meta(shareID: shareID)!      // nothing to store: notes are open to the play's members, by role
    }

    func setNotifications(shareID: String, on: Bool) async {}

    @MainActor
    func observe(shareID: String, onChange: @escaping @MainActor ([PlayComment]) -> Void) -> (@MainActor () -> Void)? {
        let reg = notes.addSnapshotListener { snap, _ in
            MainActor.assumeIsolated {
                guard let snap else { return }
                onChange(snap.documents.compactMap(Self.comment))
            }
        }
        return { reg.remove() }
    }

    /// Hidden notes never leave this function.
    private static func comment(_ d: QueryDocumentSnapshot) -> PlayComment? {
        if d["hidden"] as? Bool == true { return nil }
        func s(_ k: String) -> String? { (d[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let at = (d.get("createdAt", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date()
        return PlayComment(id: d.documentID, shareID: "", elementID: s("elementID") ?? "", quote: s("quote"),
                           body: s("body") ?? "", authorName: s("authorName") ?? "?", parentID: s("parentID"),
                           resolved: d["resolved"] as? Bool ?? false, createdAt: at, creator: s("authorUid") ?? "")
    }
}
