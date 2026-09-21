import Foundation
import CloudKit

/// Where notes live. Two homes behind one protocol: CloudKit's public database
/// (real shared readings) and an in-memory demo (DEBUG, for the simulator).
protocol CommentBackend: Sendable {
    /// The signed-in person's CloudKit user record name.
    func me() async throws -> String
    /// The owner-side settings on the PublicPlay record; nil = not published.
    func meta(shareID: String) async throws -> NotesMeta?
    func list(shareID: String) async throws -> [PlayComment]
    func post(_ draft: CommentDraft) async throws -> PlayComment
    func remove(id: String) async throws
    /// The author of a root note marks their own thread resolved / reopened.
    func setResolvedByAuthor(id: String, resolved: Bool) async throws
    /// The owner edits their PublicPlay record. nil = leave that field alone.
    func ownerUpdate(shareID: String, commentsOpen: Bool?, resolved: [String]?, hidden: [String]?) async throws -> NotesMeta
    /// Ask CloudKit to push a notification when someone adds a note to this play.
    func setNotifications(shareID: String, on: Bool) async
    /// A moderator acts directly on someone's note (shared plays only).
    func moderate(id: String, resolved: Bool?, hidden: Bool?) async throws
    /// Live updates, when the home supports them; nil = the store polls instead.
    @MainActor func observe(shareID: String, onChange: @escaping @MainActor ([PlayComment]) -> Void) -> (@MainActor () -> Void)?
}

extension CommentBackend {
    func moderate(id: String, resolved: Bool?, hidden: Bool?) async throws { throw NotesError.failed("unsupported") }
    @MainActor func observe(shareID: String, onChange: @escaping @MainActor ([PlayComment]) -> Void) -> (@MainActor () -> Void)? { nil }
}

enum NotesError: LocalizedError {
    case notSignedIn, network, notPublished, failed(String)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(localized: "Connecte-toi à iCloud pour voir et laisser des notes.")
        case .network: return String(localized: "Pas de connexion réseau.")
        case .notPublished: return String(localized: "Cette pièce n'est pas partagée.")
        case .failed(let m): return m
        }
    }
}

struct CloudKitComments: CommentBackend {
    static let commentType = "PlayComment"
    /// The field holding the reading's share id. NOT named `shareID`: CKQuery reads
    /// that predicate key as CloudKit's own system `share` reference and fails with
    /// "Unknown field '___share'" (found while priming the schema, 2026-09-19).
    static let shareField = "readingID"
    private var db: CKDatabase { CKContainer(identifier: Publish.containerID).publicCloudDatabase }
    private var container: CKContainer { CKContainer(identifier: Publish.containerID) }

    func me() async throws -> String {
        do { return try await container.userRecordID().recordName }
        catch { throw map(error) }
    }

    func meta(shareID: String) async throws -> NotesMeta? {
        do {
            let r = try await db.record(for: CKRecord.ID(recordName: shareID))
            return try await Self.meta(from: r, me: me())
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        } catch { throw map(error) }
    }

    func list(shareID: String) async throws -> [PlayComment] {
        do {
            let mine = try? await me()
            let query = CKQuery(recordType: Self.commentType, predicate: NSPredicate(format: "\(Self.shareField) == %@", shareID))
            var out: [PlayComment] = []
            var (results, cursor) = try await db.records(matching: query, resultsLimit: 200)
            for page in 0..<10 {
                for (_, r) in results { if case .success(let rec) = r { out.append(Self.comment(from: rec, me: mine)) } }
                guard let c = cursor, page < 9 else { break }
                (results, cursor) = try await db.records(continuingMatchFrom: c, resultsLimit: 200)
            }
            return out
        } catch let e as CKError where e.code == .unknownItem {
            return []   // the record type doesn't exist yet in this environment: no notes
        } catch { throw map(error) }
    }

    func post(_ d: CommentDraft) async throws -> PlayComment {
        let r = CKRecord(recordType: Self.commentType, recordID: CKRecord.ID(recordName: UUID().uuidString))
        r[Self.shareField] = d.shareID
        r["elementID"] = d.elementID
        r["body"] = d.body
        r["authorName"] = d.authorName
        r["resolved"] = 0
        if let q = d.quote, !q.isEmpty { r["quote"] = q }
        if let p = d.parentID, !p.isEmpty { r["parentID"] = p }
        do { return Self.comment(from: try await db.save(r), me: try? await me()) }
        catch { throw map(error) }
    }

    func remove(id: String) async throws {
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id)) }
        catch let e as CKError where e.code == .unknownItem { /* already gone */ }
        catch { throw map(error) }
    }

    func setResolvedByAuthor(id: String, resolved: Bool) async throws {
        do {
            let r = try await db.record(for: CKRecord.ID(recordName: id))
            r["resolved"] = resolved ? 1 : 0
            _ = try await db.save(r)
        } catch { throw map(error) }
    }

    func ownerUpdate(shareID: String, commentsOpen: Bool?, resolved: [String]?, hidden: [String]?) async throws -> NotesMeta {
        // Fetch-modify-save, retried once: a collaborator's web session may have
        // touched nothing here, but the owner's other devices can.
        for attempt in 0..<2 {
            do {
                let r = try await db.record(for: CKRecord.ID(recordName: shareID))
                if let commentsOpen { r["commentsOpen"] = commentsOpen ? 1 : 0 }
                if let resolved { r["resolvedComments"] = resolved.isEmpty ? nil : resolved }
                if let hidden { r["hiddenComments"] = hidden.isEmpty ? nil : hidden }
                return try await Self.meta(from: try await db.save(r), me: me())
            } catch let e as CKError where e.code == .serverRecordChanged && attempt == 0 {
                continue
            } catch let e as CKError where e.code == .unknownItem {
                throw NotesError.notPublished
            } catch { throw map(error) }
        }
        throw NotesError.failed("conflict")
    }

    func setNotifications(shareID: String, on: Bool) async {
        let id = "notes-" + shareID
        if on {
            let sub = CKQuerySubscription(recordType: Self.commentType,
                                          predicate: NSPredicate(format: "\(Self.shareField) == %@", shareID),
                                          subscriptionID: id, options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            // The key IS the French sentence (fr is the source language and has no
            // .lproj); en.lproj carries the English.
            info.alertLocalizationKey = "%1$@ a laissé une note sur ta pièce."
            info.alertLocalizationArgs = ["authorName"]
            info.soundName = "default"
            sub.notificationInfo = info
            _ = try? await db.save(sub)
        } else {
            _ = try? await db.deleteSubscription(withID: id)
        }
    }

    // MARK: mapping

    /// Own records come back with the placeholder `__defaultOwner__` as creator;
    /// normalise to the real user record name so "mine" is one comparison.
    private static func creator(_ r: CKRecord, me: String?) -> String {
        let name = r.creatorUserRecordID?.recordName ?? ""
        return name == CKCurrentUserDefaultName ? (me ?? name) : name
    }

    static func comment(from r: CKRecord, me: String?) -> PlayComment {
        func s(_ k: String) -> String? { (r[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return PlayComment(id: r.recordID.recordName, shareID: s(shareField) ?? "", elementID: s("elementID") ?? "",
                           quote: s("quote"), body: s("body") ?? "", authorName: s("authorName") ?? "?",
                           parentID: s("parentID"), resolved: (r["resolved"] as? Int64 ?? 0) == 1,
                           createdAt: r.creationDate ?? Date(), creator: creator(r, me: me))
    }

    static func meta(from r: CKRecord, me: String?) -> NotesMeta {
        NotesMeta(commentsOpen: (r["commentsOpen"] as? Int64 ?? 0) == 1,
                  resolved: r["resolvedComments"] as? [String] ?? [],
                  hidden: r["hiddenComments"] as? [String] ?? [],
                  owner: creator(r, me: me))
    }

    private func map(_ error: Error) -> Error {
        guard let e = error as? CKError else { return error }
        switch e.code {
        case .notAuthenticated: return NotesError.notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited: return NotesError.network
        default: return NotesError.failed(e.localizedDescription)
        }
    }
}

#if DEBUG
/// In-memory notes for the simulator (`LR_NOTES_DEMO=1`): seeded against the
/// play's real element ids so badges, threads and the detached list all show.
actor DemoComments: CommentBackend {
    static let owner = "_demo-owner"
    private var comments: [PlayComment] = []
    private var state = NotesMeta(commentsOpen: true, resolved: [], hidden: [], owner: DemoComments.owner)

    init(shareID: String, anchors: [(id: String, text: String)]) {
        func mk(_ id: String, _ el: String, _ who: String, _ body: String, hoursAgo: Double,
                quote: String? = nil, parent: String? = nil, resolved: Bool = false, creator: String = "_demo-x") -> PlayComment {
            PlayComment(id: id, shareID: shareID, elementID: el, quote: quote, body: body, authorName: who,
                        parentID: parent, resolved: resolved, createdAt: Date(timeIntervalSinceNow: -hoursAgo * 3600), creator: creator)
        }
        var seeded: [PlayComment] = []
        if anchors.count > 0 {
            let a = anchors[0]
            let quote = a.text.split(separator: " ").prefix(4).joined(separator: " ")
            seeded.append(mk("s1", a.id, "Mireille (dramaturge)", "Garde ça sec. C'est la meilleure réplique de la page.", hoursAgo: 26,
                             quote: quote.isEmpty ? nil : quote))
            seeded.append(mk("s2", a.id, "Jac", "Merci — je laisse tomber la phrase d'après.", hoursAgo: 25, parent: "s1", creator: DemoComments.owner))
        }
        if anchors.count > 1 { seeded.append(mk("s3", anchors[1].id, "Luc (metteur en scène)", "Combien de temps, concrètement ? J'ai besoin d'un chiffre pour régler le silence.", hoursAgo: 5)) }
        if anchors.count > 2 { seeded.append(mk("s4", anchors[2].id, "Luc (metteur en scène)", "On l'entend bien, c'est réglé.", hoursAgo: 4, resolved: true)) }
        seeded.append(mk("s5", "ligne-coupee", "Mireille (dramaturge)", "Cette réplique-là explique trop.", hoursAgo: 30, quote: "Tu peux pas rester là toute la nuit."))
        seeded.append(mk("s6", Notes.general, "Luc (metteur en scène)", "Lecture à la table jeudi. Le deuxième acte est le plus solide.", hoursAgo: 2))
        comments = seeded
    }

    func me() -> String { Self.owner }
    func meta(shareID: String) -> NotesMeta? { state }
    func list(shareID: String) -> [PlayComment] { comments }
    func post(_ d: CommentDraft) -> PlayComment {
        let c = PlayComment(id: UUID().uuidString, shareID: d.shareID, elementID: d.elementID, quote: d.quote, body: d.body,
                            authorName: d.authorName, parentID: d.parentID, resolved: false, createdAt: Date(), creator: Self.owner)
        comments.append(c); return c
    }
    func remove(id: String) { comments.removeAll { $0.id == id } }
    func setResolvedByAuthor(id: String, resolved: Bool) {
        if let i = comments.firstIndex(where: { $0.id == id }) { comments[i].resolved = resolved }
    }
    func ownerUpdate(shareID: String, commentsOpen: Bool?, resolved: [String]?, hidden: [String]?) -> NotesMeta {
        if let commentsOpen { state.commentsOpen = commentsOpen }
        if let resolved { state.resolved = resolved }
        if let hidden { state.hidden = hidden }
        return state
    }
    func setNotifications(shareID: String, on: Bool) {}
}
#endif
