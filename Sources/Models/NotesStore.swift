import Foundation
import SwiftUI
import UserNotifications

/// The notes of ONE play, for the views: loads them, keeps the threads and the
/// per-line counts current, and carries out the owner's and the author's actions.
@MainActor
final class NotesStore: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, unpublished, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var meta = NotesMeta()
    @Published private(set) var threads: [NoteThread] = []
    /// Open threads per element id — drives the editor's margin badges.
    @Published private(set) var openCounts: [String: Int] = [:]
    @Published private(set) var unread = 0
    @Published private(set) var me: String?
    @Published var actionError: String?

    private(set) var shareID: String?
    /// A shared (collaborative) play: notes are always on, gated by role.
    @Published private(set) var isShared = false
    /// May this person leave notes? (A reader of a shared play may not.)
    @Published private(set) var canPost = true
    private var stopObserving: (@MainActor () -> Void)?
    private var comments: [PlayComment] = []
    private var elementIDs: Set<String> = []
    private var backend: CommentBackend = CloudKitComments()
    private var poll: Task<Void, Never>?

    static let pollSeconds: UInt64 = 60

    /// Point the store at a play. Call again whenever the share id or the set of
    /// elements changes; it only refetches when the share id did.
    func attach(shareID: String?, elementIDs: Set<String>, backend: CommentBackend? = nil,
                shared: Bool = false, canPost: Bool = true) {
        if let backend { self.backend = backend }
        self.elementIDs = elementIDs
        if self.canPost != canPost { self.canPost = canPost }
        guard shareID != self.shareID else { rebuild(); return }
        self.shareID = shareID
        isShared = shared
        comments = []; meta = NotesMeta(); rebuild()
        poll?.cancel(); stopObserving?(); stopObserving = nil
        guard let shareID else { phase = .unpublished; return }
        phase = .loading
        // A live home pushes every change; otherwise fall back to polling.
        if let stop = self.backend.observe(shareID: shareID, onChange: { [weak self] list in
            guard let self else { return }
            self.comments = list
            self.phase = .ready
            self.rebuild()
        }) {
            stopObserving = stop
            Task { [weak self] in await self?.refresh() }
            return
        }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
            }
        }
    }

    func detach() { poll?.cancel(); poll = nil; stopObserving?(); stopObserving = nil }

    func refresh() async {
        guard let shareID else { return }
        do {
            if me == nil { me = try? await backend.me() }
            guard let m = try await backend.meta(shareID: shareID) else { phase = .unpublished; return }
            meta = m
            comments = m.commentsOpen || !comments.isEmpty ? try await backend.list(shareID: shareID) : []
            phase = .ready
            rebuild()
        } catch {
            // A failed background refresh keeps what's on screen.
            if phase != .ready { phase = .failed(error.localizedDescription) }
        }
    }

    private func rebuild() {
        threads = Notes.threads(comments, meta: meta, elementIDs: elementIDs)
        openCounts = Notes.openCounts(threads)
        unread = Notes.unread(comments, meta: meta, since: lastSeen, me: me)
    }

    // MARK: seen / unread

    private var seenKey: String { "notes.seen." + (shareID ?? "") }
    private var lastSeen: Date? { UserDefaults.standard.object(forKey: seenKey) as? Date }
    func markSeen() {
        guard shareID != nil else { return }
        UserDefaults.standard.set(Date(), forKey: seenKey)
        rebuild()
        if let shareID { NotesInbox.shared.clear(shareID) }
    }

    // MARK: actions

    func setOpen(_ open: Bool) async {
        guard let shareID else { return }
        await run {
            self.meta = try await self.backend.ownerUpdate(shareID: shareID, commentsOpen: open, resolved: nil, hidden: nil)
            if open {
                // Ask once, at the moment it makes sense: the owner just invited notes.
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                if granted { Self.registerForPush() }
                await self.backend.setNotifications(shareID: shareID, on: granted)
                await self.refresh()
            } else {
                await self.backend.setNotifications(shareID: shareID, on: false)
            }
            self.rebuild()
        }
    }

    @discardableResult
    func post(elementID: String, quote: String? = nil, body: String, parentID: String? = nil, authorName: String) async -> Bool {
        guard let shareID, case .success(let text) = Notes.validBody(body),
              case .success(let name) = Notes.validName(authorName) else { return false }
        return await run {
            let saved = try await self.backend.post(CommentDraft(shareID: shareID, elementID: elementID, quote: quote,
                                                                 body: text, authorName: name, parentID: parentID))
            // With a live listener the same note may already be here — never twice.
            if !self.comments.contains(where: { $0.id == saved.id }) { self.comments.append(saved) }
            self.rebuild()
        }
    }

    func remove(_ c: PlayComment) async {
        await run {
            try await self.backend.remove(id: c.id)
            self.comments.removeAll { $0.id == c.id }
            self.rebuild()
        }
    }

    func hide(_ c: PlayComment) async {
        guard let shareID else { return }
        if meta.viewerCanModerate {
            await run {
                try await self.backend.moderate(id: c.id, resolved: nil, hidden: true)
                self.comments.removeAll { $0.id == c.id || $0.parentID == c.id }
                self.rebuild()
            }
            return
        }
        await run {
            let hidden = Array(Set(self.meta.hidden + [c.id]))
            self.meta = try await self.backend.ownerUpdate(shareID: shareID, commentsOpen: nil, resolved: nil, hidden: hidden)
            self.rebuild()
        }
    }

    func setResolved(_ t: NoteThread, _ resolved: Bool) async {
        guard let shareID else { return }
        await run {
            let mine = !t.rootDeleted && self.me == t.root.creator
            if self.meta.viewerCanModerate, !t.rootDeleted {
                // Shared play: `resolved` is a field on the note; the server lets its
                // author and every writer set it.
                try await self.backend.setResolvedByAuthor(id: t.root.id, resolved: resolved)
                self.patch(t.root.id) { $0.resolved = resolved }
                self.rebuild()
                return
            }
            if resolved {
                if mine {
                    try await self.backend.setResolvedByAuthor(id: t.root.id, resolved: true)
                    self.patch(t.root.id) { $0.resolved = true }
                } else {
                    let list = Array(Set(self.meta.resolved + [t.key]))
                    self.meta = try await self.backend.ownerUpdate(shareID: shareID, commentsOpen: nil, resolved: list, hidden: nil)
                }
            } else {
                if mine && t.root.resolved {
                    try await self.backend.setResolvedByAuthor(id: t.root.id, resolved: false)
                    self.patch(t.root.id) { $0.resolved = false }
                }
                if self.meta.resolved.contains(t.key) {
                    let list = self.meta.resolved.filter { $0 != t.key }
                    self.meta = try await self.backend.ownerUpdate(shareID: shareID, commentsOpen: nil, resolved: list, hidden: nil)
                }
            }
            self.rebuild()
        }
    }

    func rights(_ c: PlayComment) -> Notes.Rights { Notes.rights(viewer: me, meta: meta, c) }
    func canReopen(_ t: NoteThread) -> Bool { Notes.canReopen(t, viewer: me, meta: meta) }

    private func patch(_ id: String, _ edit: (inout PlayComment) -> Void) {
        if let i = comments.firstIndex(where: { $0.id == id }) { edit(&comments[i]) }
    }

    @discardableResult
    private func run(_ op: @escaping () async throws -> Void) async -> Bool {
        do { try await op(); actionError = nil; return true }
        catch { actionError = error.localizedDescription; return false }
    }

    private static func registerForPush() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}

/// Unread-note counts for the library sidebar: one light pass over the
/// published plays when the app comes forward. Failures are silent.
@MainActor
final class NotesInbox: ObservableObject {
    static let shared = NotesInbox()
    @Published private(set) var unread: [String: Int] = [:]
    private var backend: CommentBackend = CloudKitComments()
    private var lastRun = Date.distantPast

    func refresh(shareIDs: [String]) async {
        guard !shareIDs.isEmpty, Date().timeIntervalSince(lastRun) > 30 else { return }
        lastRun = Date()
        guard let me = try? await backend.me() else { return }
        for id in shareIDs.prefix(25) {
            guard let meta = try? await backend.meta(shareID: id), meta.commentsOpen,
                  let list = try? await backend.list(shareID: id) else { continue }
            let since = UserDefaults.standard.object(forKey: "notes.seen." + id) as? Date
            unread[id] = Notes.unread(list, meta: meta, since: since, me: me)
        }
    }

    func clear(_ shareID: String) { unread[shareID] = 0 }
}
