import Foundation
import SwiftData

/// The sync engine's heart: keeps one local `Play` and its shared copy in step.
///
/// The editor never learns the play is shared — it keeps reading and writing the
/// same SwiftData objects. This sits beside it:
///
///   flushLocal()   local play  ─diff vs shadow→  ops to send
///   applyRemote()  changes from others  ─→  local objects (+ reorder)
///
/// `shadow` is the last state both sides agreed on, per entity and per field. It
/// makes every merge three-way: a field that differs from the shadow locally is
/// MY edit; one that differs remotely is THEIRS. It is persisted (`shadowData`)
/// so edits made offline, or just before a relaunch, still merge correctly.
///
/// Synchronous and transport-free on purpose: the convergence tests drive it
/// directly against a simulated server. `CollabSession` adds time and network.
@MainActor
final class CollabCore {
    let play: Play
    private let context: ModelContext
    private(set) var shadow: [EntityRef: Fields]

    /// Past this, an order key is re-minted for the whole list (one batch).
    static let rebalanceAt = 40

    init(play: Play, context: ModelContext, shadowData: Data? = nil) {
        self.play = play
        self.context = context
        self.shadow = shadowData.flatMap { try? JSONDecoder().decode([Stored].self, from: $0) }
            .map { Dictionary(uniqueKeysWithValues: $0.map { ($0.ref, $0.fields) }) } ?? [:]
    }

    private struct Stored: Codable { var ref: EntityRef; var fields: Fields }
    var shadowData: Data {
        (try? JSONEncoder().encode(shadow.map { Stored(ref: $0.key, fields: $0.value) })) ?? Data()
    }

    // MARK: - local → ops

    /// Everything that changed locally since the last flush, as ops. The shadow
    /// moves forward at once (optimistically): the transport's overlay contract
    /// guarantees we won't be told an older value while these are in flight.
    func flushLocal() -> [CollabOp] {
        var local: [EntityRef: Fields] = [.info: Self.fields(of: play)]
        for c in play.characters ?? [] { local[EntityRef(kind: .character, id: c.id.uuidString)] = Self.fields(of: c) }
        let ordered = play.elementList
        let keys = orderKeys(for: ordered)
        for (el, key) in zip(ordered, keys) {
            var f = Self.fields(of: el)
            f[CollabField.orderKey] = key
            local[EntityRef(kind: .element, id: el.id.uuidString)] = f
        }

        var ops: [CollabOp] = []
        for (ref, now) in local {
            guard let was = shadow[ref] else { ops.append(.put(ref, now)); continue }
            let set = now.filter { was[$0.key] != $0.value }
            let unset = was.keys.filter { now[$0] == nil }
            if !set.isEmpty || !unset.isEmpty { ops.append(.patch(ref, set: set, unset: unset.sorted())) }
        }
        for ref in shadow.keys where local[ref] == nil { ops.append(.delete(ref)) }
        shadow = local
        // Deterministic order: creations before edits before deletions, then by ref.
        return ops.sorted { Self.rank($0) != Self.rank($1) ? Self.rank($0) < Self.rank($1) : $0.ref.description < $1.ref.description }
    }

    private static func rank(_ op: CollabOp) -> Int {
        switch op { case .put: return 0; case .patch: return 1; case .delete: return 2 }
    }

    /// An order key for each element, in local order. Keys already agreed on are
    /// kept wherever they still read in order (the longest such run); only the
    /// blocks that were inserted or moved get new keys, minted between their
    /// neighbours — so a reorder touches the blocks that moved and nobody else's.
    private func orderKeys(for ordered: [Element]) -> [String] {
        var keys: [String?] = ordered.map { shadow[EntityRef(kind: .element, id: $0.id.uuidString)]?[CollabField.orderKey] }
        let keep = Self.longestIncreasingRun(keys)
        for i in keys.indices where !keep.contains(i) { keys[i] = nil }

        var out = [String](repeating: "", count: keys.count)
        var prev: String?
        var i = 0
        while i < keys.count {
            if let k = keys[i] { out[i] = k; prev = k; i += 1; continue }
            var j = i
            while j < keys.count, keys[j] == nil { j += 1 }
            let next = j < keys.count ? keys[j] : nil
            for n in i..<j { let k = FractionalIndex.between(prev, next); out[n] = k; prev = k }
            i = j
        }
        if out.contains(where: { $0.count > Self.rebalanceAt }) { return FractionalIndex.spread(out.count) }
        return out
    }

    /// Indices of the longest strictly increasing subsequence of the non-nil keys.
    static func longestIncreasingRun(_ keys: [String?]) -> Set<Int> {
        var tails: [Int] = []                       // tails[l] = index ending the best run of length l+1
        var back = [Int](repeating: -1, count: keys.count)
        for (i, k) in keys.enumerated() {
            guard let k else { continue }
            var lo = 0, hi = tails.count
            while lo < hi { let mid = (lo + hi) / 2; if keys[tails[mid]]! < k { lo = mid + 1 } else { hi = mid } }
            back[i] = lo > 0 ? tails[lo - 1] : -1
            if lo == tails.count { tails.append(i) } else { tails[lo] = i }
        }
        var out = Set<Int>()
        var at = tails.last ?? -1
        while at >= 0 { out.insert(at); at = back[at] }
        return out
    }

    // MARK: - remote → local

    /// Apply what others did. Local edits are flushed FIRST, so anything typed
    /// since the last tick is captured as "mine" before "theirs" lands; those ops
    /// are returned for the caller to send.
    @discardableResult
    func applyRemote(_ changes: [RemoteChange]) -> [CollabOp] {
        let mine = flushLocal()
        // A line I deleted a moment ago (not yet flushed when this batch was
        // composed) may still arrive as "edited by someone else". Delete wins:
        // don't bring it back for the instant before the server agrees.
        let justDeleted = Set(mine.compactMap { op -> EntityRef? in if case .delete(let r) = op { return r }; return nil })
        var orderTouched = false
        for change in changes {
            switch change {
            case .upsert(let ref, let theirs):
                if justDeleted.contains(ref) { continue }
                let was = shadow[ref]
                if was == theirs { continue }                         // our own echo, or nothing new
                shadow[ref] = theirs
                if ref.kind == .element, was?[CollabField.orderKey] != theirs[CollabField.orderKey] { orderTouched = true }
                write(ref, theirs, changed: Self.changedKeys(from: was, to: theirs))
            case .removed(let ref):
                guard shadow.removeValue(forKey: ref) != nil || object(ref) != nil else { continue }
                remove(ref)
                if ref.kind == .element { orderTouched = true }
            }
        }
        if orderTouched { reorderFromKeys() }
        return mine
    }

    /// Build the local play from a shared one (joining). The shadow becomes that
    /// state, so nothing is echoed back.
    func adopt(_ all: [EntityRef: Fields]) {
        for el in play.elements ?? [] { el.play = nil; context.delete(el) }
        for c in play.characters ?? [] { c.play = nil; context.delete(c) }
        shadow = [:]
        let order: [EntityKind: Int] = [.info: 0, .character: 1, .element: 2]
        for (ref, f) in all.sorted(by: { order[$0.key.kind]! < order[$1.key.kind]! }) {
            shadow[ref] = f
            write(ref, f, changed: Set(f.keys))
        }
        reorderFromKeys()
    }

    private static func changedKeys(from was: Fields?, to now: Fields) -> Set<String> {
        guard let was else { return Set(now.keys) }
        return Set(now.filter { was[$0.key] != $0.value }.keys).union(was.keys.filter { now[$0] == nil })
    }

    private func object(_ ref: EntityRef) -> AnyObject? {
        switch ref.kind {
        case .info: return play
        case .character: return (play.characters ?? []).first { $0.id.uuidString == ref.id }
        case .element: return (play.elements ?? []).first { $0.id.uuidString == ref.id }
        }
    }

    private func write(_ ref: EntityRef, _ f: Fields, changed: Set<String>) {
        guard let uuid = ref.kind == .info ? play.id : UUID(uuidString: ref.id) else { return }
        switch ref.kind {
        case .info:
            Self.apply(f, changed, to: play)
        case .character:
            let c = (object(ref) as? Character) ?? {
                let c = Character(); c.id = uuid; c.play = play; context.insert(c); return c
            }()
            Self.apply(f, changed, to: c)
        case .element:
            let el = (object(ref) as? Element) ?? {
                let el = Element(); el.id = uuid; el.order = Int.max; el.play = play; context.insert(el); return el
            }()
            Self.apply(f, changed, to: el)
        }
    }

    private func remove(_ ref: EntityRef) {
        switch object(ref) {
        case let c as Character:
            // Same rule as the editor: a removed character's lines stay, unassigned.
            c.play = nil; context.delete(c)
        case let el as Element:
            el.play = nil; context.delete(el)
        default: break
        }
    }

    /// Renumber the dense local `order` from the agreed keys. Equal keys (two
    /// people inserting into the same gap at the same instant) fall back to the
    /// element id, so every client breaks the tie the same way.
    private func reorderFromKeys() {
        let sorted = (play.elements ?? []).sorted {
            let a = shadow[EntityRef(kind: .element, id: $0.id.uuidString)]?[CollabField.orderKey] ?? "~"
            let b = shadow[EntityRef(kind: .element, id: $1.id.uuidString)]?[CollabField.orderKey] ?? "~"
            return a != b ? a < b : $0.id.uuidString < $1.id.uuidString
        }
        for (i, el) in sorted.enumerated() where el.order != i { el.order = i }
    }

    // MARK: - object ⇄ fields

    static func fields(of p: Play) -> Fields {
        var f: Fields = [CollabField.title: p.title, CollabField.subtitle: p.subtitle, CollabField.author: p.author,
                         CollabField.logline: p.logline, CollabField.lang: p.langRaw]
        f[CollabField.altLang] = p.altLangRaw
        return f
    }

    static func fields(of c: Character) -> Fields {
        var f: Fields = [CollabField.name: c.name, CollabField.color: c.colorHex, CollabField.order: String(c.order)]
        f[CollabField.note] = c.note
        f[CollabField.voiceID] = c.voiceID
        return f
    }

    static func fields(of e: Element) -> Fields {
        var f: Fields = [CollabField.kind: e.kindRaw]
        f[CollabField.characterID] = e.characterID
        f[CollabField.text] = e.text
        f[CollabField.label] = e.label
        f[CollabField.setting] = e.setting
        f[CollabField.synopsis] = e.synopsis
        f[CollabField.beat] = e.beatRaw
        f[CollabField.parenthetical] = e.parenthetical
        f[CollabField.alt] = e.alt
        return f
    }

    private static func apply(_ f: Fields, _ changed: Set<String>, to p: Play) {
        for k in changed {
            switch k {
            case CollabField.title: p.title = f[k] ?? ""
            case CollabField.subtitle: p.subtitle = f[k] ?? ""
            case CollabField.author: p.author = f[k] ?? ""
            case CollabField.logline: p.logline = f[k] ?? ""
            case CollabField.lang: p.langRaw = f[k] ?? Lang.fr.rawValue
            case CollabField.altLang: p.altLangRaw = f[k]
            default: break
            }
        }
    }

    private static func apply(_ f: Fields, _ changed: Set<String>, to c: Character) {
        for k in changed {
            switch k {
            case CollabField.name: c.name = f[k] ?? ""
            case CollabField.color: c.colorHex = f[k] ?? "#4f7cff"
            case CollabField.order: c.order = f[k].flatMap(Int.init) ?? 0
            case CollabField.note: c.note = f[k]
            case CollabField.voiceID: c.voiceID = f[k]
            default: break
            }
        }
    }

    private static func apply(_ f: Fields, _ changed: Set<String>, to e: Element) {
        for k in changed {
            switch k {
            case CollabField.kind: e.kindRaw = f[k] ?? ElementKind.cue.rawValue
            case CollabField.characterID: e.characterID = f[k]
            case CollabField.text: e.text = f[k]
            case CollabField.label: e.label = f[k]
            case CollabField.setting: e.setting = f[k]
            case CollabField.synopsis: e.synopsis = f[k]
            case CollabField.beat: e.beatRaw = f[k]
            case CollabField.parenthetical: e.parenthetical = f[k]
            case CollabField.alt: e.alt = f[k]
            default: break                                            // orderKey lives in the shadow only
            }
        }
    }
}
