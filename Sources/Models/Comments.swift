import Foundation

// Notes on a shared reading — the pure rules. This file mirrors the web viewer's
// `src/lire/comments.ts` line for line (same rules, same tests), so a thread
// looks the same in the app and on the web.
//
// Storage model (CloudKit PUBLIC database, default security roles only):
//   • PlayComment — one record per note, created by whoever wrote it. Only its
//     creator can modify or delete it.
//   • PublicPlay  — the owner's record. Owner moderation lives THERE, because the
//     owner cannot touch other people's records: `commentsOpen`, plus the lists
//     `resolvedComments` and `hiddenComments` (comment record names).

struct PlayComment: Identifiable, Equatable, Sendable {
    var id: String
    var shareID: String
    /// The `Element.id` it is anchored to; "" = a note about the whole play.
    var elementID: String
    var quote: String?
    var body: String
    var authorName: String
    /// Root note's id when this is a reply.
    var parentID: String?
    /// Set by the note's own author on a root note.
    var resolved: Bool
    var createdAt: Date
    /// CloudKit user record name of whoever created it.
    var creator: String
}

struct NotesMeta: Equatable, Sendable {
    var commentsOpen = false
    var resolved: [String] = []
    var hidden: [String] = []
    /// The play's owner (CloudKit user record name, or Firebase uid).
    var owner = ""
    /// In a shared play every WRITER moderates (resolve, reopen, hide) — the
    /// server's rules allow it directly on the note. On a CloudKit reading only
    /// the owner does, through lists on their own record.
    var viewerCanModerate = false
}

struct CommentDraft: Sendable {
    var shareID: String
    var elementID: String
    var quote: String?
    var body: String
    var authorName: String
    var parentID: String?
}

struct NoteThread: Identifiable, Equatable, Sendable {
    var root: PlayComment
    var replies: [PlayComment]
    var resolved: Bool
    /// Its line no longer exists in the play.
    var detached: Bool
    /// The original root was deleted; the earliest surviving reply stands in.
    var rootDeleted: Bool

    var id: String { root.id }
    /// The id the owner's resolved/hidden lists refer to for this thread.
    var key: String { rootDeleted ? (root.parentID ?? root.id) : root.id }
    var all: [PlayComment] { [root] + replies }
}

enum Notes {
    static let maxBody = 2000
    static let maxName = 40
    static let maxQuote = 280
    /// elementID of a note about the play as a whole.
    static let general = ""

    /// Group notes into threads.
    ///  - hidden notes vanish (a hidden root takes its replies with it);
    ///  - a reply whose root is gone is kept: the earliest orphan stands in as
    ///    root, so nobody's note disappears silently;
    ///  - resolved = the author resolved it OR the owner listed it;
    ///  - detached = anchored to an element that is no longer in the play.
    static func threads(_ comments: [PlayComment], meta: NotesMeta, elementIDs: Set<String>) -> [NoteThread] {
        let hidden = Set(meta.hidden), ownerResolved = Set(meta.resolved)
        let visible = comments.filter { !hidden.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        func isDetached(_ c: PlayComment) -> Bool { c.elementID != general && !elementIDs.contains(c.elementID) }

        var order: [String] = []
        var byRoot: [String: NoteThread] = [:]
        for c in visible where c.parentID == nil {
            byRoot[c.id] = NoteThread(root: c, replies: [], resolved: c.resolved || ownerResolved.contains(c.id),
                                      detached: isDetached(c), rootDeleted: false)
            order.append(c.id)
        }
        let hiddenRoots = Set(comments.filter { $0.parentID == nil && hidden.contains($0.id) }.map(\.id))
        for c in visible {
            guard let parent = c.parentID, !hiddenRoots.contains(parent) else { continue }
            if byRoot[parent] != nil {
                byRoot[parent]!.replies.append(c)
            } else {
                // Orphan: stands in as root under the missing parent's key.
                let k = "orphan:" + parent
                if byRoot[k] != nil { byRoot[k]!.replies.append(c) }
                else {
                    byRoot[k] = NoteThread(root: c, replies: [], resolved: ownerResolved.contains(parent),
                                           detached: isDetached(c), rootDeleted: true)
                    order.append(k)
                }
            }
        }
        return order.compactMap { byRoot[$0] }.sorted { $0.root.createdAt < $1.root.createdAt }
    }

    static func threads(_ all: [NoteThread], for elementID: String) -> [NoteThread] {
        all.filter { !$0.detached && $0.root.elementID == elementID }
    }

    /// Open-thread count per element id (what the editor's margin badges show).
    static func openCounts(_ all: [NoteThread]) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in all where !t.resolved && !t.detached { out[t.root.elementID, default: 0] += 1 }
        return out
    }

    static func counts(_ all: [NoteThread]) -> (open: Int, resolved: Int, detached: Int) {
        (all.filter { !$0.resolved }.count, all.filter(\.resolved).count, all.filter(\.detached).count)
    }

    enum Invalid: Error, Equatable { case empty, tooLong }

    static func validBody(_ raw: String) -> Result<String, Invalid> {
        let v = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return .failure(.empty) }
        return v.count > maxBody ? .failure(.tooLong) : .success(v)
    }

    static func validName(_ raw: String) -> Result<String, Invalid> {
        let v = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if v.isEmpty { return .failure(.empty) }
        return v.count > maxName ? .failure(.tooLong) : .success(v)
    }

    struct Rights: Equatable { var remove: Bool; var hide: Bool; var resolve: Bool }

    /// What a viewer may do to a note.
    static func rights(viewer: String?, meta: NotesMeta, _ c: PlayComment) -> Rights {
        let mine = viewer != nil && viewer == c.creator
        let moderates = viewer != nil && (viewer == meta.owner || meta.viewerCanModerate)
        return Rights(remove: mine, hide: moderates && !mine, resolve: c.parentID == nil && (mine || moderates))
    }

    /// Can the viewer clear every "resolved" flag currently set on this thread?
    static func canReopen(_ t: NoteThread, viewer: String?, meta: NotesMeta) -> Bool {
        let authorFlag = !t.rootDeleted && t.root.resolved
        let ownerFlag = meta.resolved.contains(t.key)
        guard authorFlag || ownerFlag else { return false }
        if authorFlag && viewer != t.root.creator && !meta.viewerCanModerate { return false }
        if ownerFlag && viewer != meta.owner && !meta.viewerCanModerate { return false }
        return true
    }

    /// Notes by other people created after `since` — the "unread" count.
    static func unread(_ comments: [PlayComment], meta: NotesMeta, since: Date?, me: String?) -> Int {
        let hidden = Set(meta.hidden)
        return comments.filter { !hidden.contains($0.id) && $0.creator != me && (since == nil || $0.createdAt > since!) }.count
    }
}
