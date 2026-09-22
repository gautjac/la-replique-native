import Foundation

/// A line-by-line comparison of two states of a play, by element id — so a
/// moved line is a move, not a deletion plus an addition. Mirrored by the web's
/// `src/collab/playDiff.ts` (same rows on the same input; shared test vectors).
enum PlayDiff {
    enum Row: Equatable {
        case same(ElDoc)
        case added(ElDoc)
        case removed(ElDoc)
        case changed(from: ElDoc, to: ElDoc)
        case moved(ElDoc)

        var doc: ElDoc { switch self { case .same(let d), .added(let d), .removed(let d), .moved(let d): return d; case .changed(_, let d): return d } }
        var isChange: Bool { if case .same = self { return false }; return true }
    }

    /// `a` = before, `b` = after. Walks both in order: a line in both at the same
    /// point is same/changed; a line only in `a` is removed where it was; only in
    /// `b` is added where it is; in both but out of order is a move (reported once,
    /// where it lands).
    static func compare(_ a: [ElDoc], _ b: [ElDoc]) -> [Row] {
        let inB = Set(b.compactMap(\.id)), inA = Set(a.compactMap(\.id))
        var consumed = Set<String>()
        var rows: [Row] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, let ida = a[i].id, consumed.contains(ida) { i += 1; continue }
            if i < a.count, j < b.count, a[i].id != nil, a[i].id == b[j].id {
                rows.append(same(a[i], b[j]) ? .same(b[j]) : .changed(from: a[i], to: b[j])); i += 1; j += 1
            } else if i < a.count, !(a[i].id.map { inB.contains($0) } ?? false) {
                rows.append(.removed(a[i])); i += 1
            } else if j < b.count, !(b[j].id.map { inA.contains($0) } ?? false) {
                rows.append(.added(b[j])); j += 1
            } else if j < b.count {
                // Both sides have it, at different places: it moved here.
                if let id = b[j].id { consumed.insert(id) }
                if let old = a.first(where: { $0.id == b[j].id }), !same(old, b[j]) { rows.append(.changed(from: old, to: b[j])) }
                else { rows.append(.moved(b[j])) }
                j += 1
            } else {
                i += 1
            }
        }
        return rows
    }

    /// Same content (ids and order aside).
    static func same(_ x: ElDoc, _ y: ElDoc) -> Bool {
        x.type == y.type && x.text == y.text && x.label == y.label && x.setting == y.setting
            && x.character == y.character && x.parenthetical == y.parenthetical && x.beat == y.beat && x.synopsis == y.synopsis
    }

    static func summary(_ rows: [Row]) -> (added: Int, removed: Int, changed: Int, moved: Int) {
        var s = (0, 0, 0, 0)
        for r in rows { switch r { case .added: s.0 += 1; case .removed: s.1 += 1; case .changed: s.2 += 1; case .moved: s.3 += 1; case .same: break } }
        return s
    }
}
