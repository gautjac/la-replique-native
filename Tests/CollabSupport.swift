import Foundation
import SwiftData
@testable import LaReplique

/// A stand-in for Firestore, faithful to the three behaviours the engine relies on:
/// field-level merges, a patch that FAILS on a missing document, and listeners
/// that see server state overlaid with their own pending writes.
@MainActor
final class FakeServer {
    private(set) var docs: [EntityRef: Fields] = [:]
    private(set) var log: [RemoteChange] = []

    /// Returns the log length after the commit, or nil when the op was rejected.
    func commit(_ op: CollabOp) -> Int? {
        switch op {
        case .put(let ref, let f):
            docs[ref] = f; log.append(.upsert(ref, f))
        case .patch(let ref, let set, let unset):
            guard var d = docs[ref] else { return nil }
            for (k, v) in set { d[k] = v }
            for k in unset { d[k] = nil }
            docs[ref] = d; log.append(.upsert(ref, d))
        case .delete(let ref):
            guard docs.removeValue(forKey: ref) != nil else { return log.count }
            log.append(.removed(ref))
        }
        return log.count
    }
}

/// One person's device: a local play + the engine + the SDK-like plumbing.
@MainActor
final class Peer {
    let name: String
    let container: ModelContainer
    let context: ModelContext
    let play: Play
    private(set) var core: CollabCore
    let server: FakeServer
    var online = true

    private var queued: [CollabOp] = []                       // written locally, not yet sent
    private var sent: [(op: CollabOp, version: Int)] = []     // sent, awaiting our listener catching up
    private var seen = 0
    private var serverView: [EntityRef: Fields] = [:]
    private var lastView: [EntityRef: Fields] = [:]

    init(_ name: String, server: FakeServer, json: String? = nil) throws {
        self.name = name; self.server = server
        let schema = Schema([Play.self, Character.self, Element.self, Version.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        if let json { play = PlayFormat.makePlay(from: try PlayFormat.decode(Data(json.utf8)), into: context) }
        else { play = Play(title: "", lang: .fr); context.insert(play) }
        core = CollabCore(play: play, context: context)
    }

    /// Simulates quitting and relaunching the app: the engine is rebuilt from its
    /// persisted shadow; the local play (SwiftData) is as the user left it.
    func relaunch() { core = CollabCore(play: play, context: context, shadowData: core.shadowData) }

    /// Joining: take the server's current state as the play.
    func join() {
        seen = server.log.count
        serverView = server.docs
        lastView = serverView
        core.adopt(serverView)
    }

    func tick() { queued += core.flushLocal(); deliver() }

    func upload() {
        guard online else { return }
        for op in queued { if let v = server.commit(op) { sent.append((op, v)) } }
        queued = []
        deliver()   // a rejected write vanishes from our overlay at once
    }

    /// Hear about up to `count` more server changes (nil = everything).
    func receive(_ count: Int? = nil) {
        guard online else { return }
        let upTo = min(server.log.count, seen + (count ?? Int.max - seen))
        for change in server.log[seen..<upTo] {
            switch change {
            case .upsert(let r, let f): serverView[r] = f
            case .removed(let r): serverView[r] = nil
            }
        }
        seen = upTo
        sent.removeAll { $0.version <= seen }
        deliver()
    }

    private func composed() -> [EntityRef: Fields] {
        var view = serverView
        for op in sent.map(\.op) + queued {
            switch op {
            case .put(let r, let f): view[r] = f
            case .patch(let r, let set, let unset):
                guard var d = view[r] else { continue }
                for (k, v) in set { d[k] = v }
                for k in unset { d[k] = nil }
                view[r] = d
            case .delete(let r): view[r] = nil
            }
        }
        return view
    }

    private func deliver() {
        let view = composed()
        var changes: [RemoteChange] = []
        for (r, f) in view where lastView[r] != f { changes.append(.upsert(r, f)) }
        for r in lastView.keys where view[r] == nil { changes.append(.removed(r)) }
        lastView = view
        guard !changes.isEmpty else { return }
        let mine = core.applyRemote(changes)
        queued += mine
        // Writes issued during a callback change what the listener sees, and a real
        // SDK then reports THAT (e.g. `removed` for a line we just deleted). Swallowing
        // it here once hid a resurrection bug — keep this faithful.
        if !mine.isEmpty { deliver() }
    }

    // MARK: what the user does

    var lines: [Element] { play.elementList }
    func line(_ text: String) -> Element? { lines.first { $0.text == text } }

    @discardableResult
    func insert(after: Element?, text: String, kind: ElementKind = .cue) -> Element {
        let el = Editing.insert(kind, after: after, play: play, context: context)
        el.text = text
        return el
    }
    func delete(_ el: Element) { Editing.remove(el, play: play, context: context) }
    func move(_ el: Element, to index: Int) {
        var arr = lines.filter { $0.id != el.id }
        arr.insert(el, at: min(max(index, 0), arr.count))
        for (i, e) in arr.enumerated() { e.order = i }
    }

    /// The whole play as comparable text — order, ids, every synced field.
    var fingerprint: String {
        let info = CollabCore.fields(of: play).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let cast = (play.characters ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            .map { c in c.id.uuidString + CollabCore.fields(of: c).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
        let els: [String] = lines.map { e in String(e.id.uuidString.prefix(8)) + ":" + CollabCore.fields(of: e).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
        return ([info] + cast + els).joined(separator: "\n")
    }
    var texts: [String] { lines.map { $0.text ?? $0.label ?? "" } }
}

@MainActor
func settle(_ peers: [Peer]) {
    for p in peers { p.online = true }
    for _ in 0..<6 { for p in peers { p.tick(); p.upload() }; for p in peers { p.receive() } }
}

/// Tiny deterministic generator so a failing fuzz seed can be replayed.
struct Lcg: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
