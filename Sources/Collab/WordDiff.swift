import SwiftUI

/// A word-level comparison of two texts — what the history and the version
/// comparison show instead of the whole line twice. Tokens are runs of
/// non-blanks, runs of blanks, and single newlines; the diff is a plain LCS
/// (deterministic, no heuristics) so the web twin `src/collab/wordDiff.ts`
/// produces the same segments on the same input (shared test vectors).
///
/// A long cue is then *focused*: only the verses that changed, with one verse
/// of context on each side, and « ⋯ » where verses were skipped.
enum WordDiff {
    enum Segment: Equatable {
        case same(String), removed(String), inserted(String)
        var text: String { switch self { case .same(let s), .removed(let s), .inserted(let s): return s } }
        var isSame: Bool { if case .same = self { return true }; return false }
    }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var blank: Bool?
        for ch in s {
            if ch == "\n" {
                if !cur.isEmpty { out.append(cur); cur = "" }
                out.append("\n"); blank = nil
                continue
            }
            let b = ch.isWhitespace
            if let blank, blank != b { out.append(cur); cur = "" }
            cur.append(ch); blank = b
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Above this many cell comparisons the line is shown as replaced outright.
    static let cap = 250_000

    static func compute(_ old: String, _ new: String) -> [Segment] {
        if old == new { return old.isEmpty ? [] : [.same(old)] }
        let a = tokens(old), b = tokens(new)
        if a.isEmpty { return [.inserted(new)] }
        if b.isEmpty { return [.removed(old)] }
        if a.count * b.count > cap { return [.removed(old), .inserted(new)] }
        let n = a.count, m = b.count
        var L = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                L[i][j] = a[i] == b[j] ? L[i + 1][j + 1] + 1 : max(L[i + 1][j], L[i][j + 1])
            }
        }
        // Walk forward; at a fork prefer removing (old text first, then new).
        var raw: [Segment] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] { raw.append(.same(a[i])); i += 1; j += 1 }
            else if j == m || (i < n && L[i + 1][j] >= L[i][j + 1]) { raw.append(.removed(a[i])); i += 1 }
            else { raw.append(.inserted(b[j])); j += 1 }
        }
        return normalise(raw)
    }

    /// Within each run of changes put removals before insertions, then merge
    /// neighbours of the same kind.
    private static func normalise(_ raw: [Segment]) -> [Segment] {
        var out: [Segment] = []
        var pendingRemoved = "", pendingInserted = ""
        func flush() {
            if !pendingRemoved.isEmpty { out.append(.removed(pendingRemoved)); pendingRemoved = "" }
            if !pendingInserted.isEmpty { out.append(.inserted(pendingInserted)); pendingInserted = "" }
        }
        for s in raw {
            switch s {
            case .same(let t):
                flush()
                if case .same(let prev)? = out.last { out[out.count - 1] = .same(prev + t) } else { out.append(.same(t)) }
            case .removed(let t): pendingRemoved += t
            case .inserted(let t): pendingInserted += t
            }
        }
        flush()
        return out
    }

    // MARK: lines and focus

    /// The merged diff, verse by verse.
    struct Line: Equatable {
        var segments: [Segment] = []
        var changed = false
    }
    enum Focused: Equatable { case line(Line), gap }

    /// A newline that came or went shows as « ↵ » in the change's colour: an
    /// inserted break ends the verse there; a removed one joins two verses.
    static let newlineMark = "↵"

    static func lines(_ segs: [Segment]) -> [Line] {
        var out: [Line] = []
        var cur = Line()
        func push(_ s: Segment) { cur.segments.append(s); if !s.isSame { cur.changed = true } }
        for seg in segs {
            let parts = seg.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, part) in parts.enumerated() {
                if i > 0 {
                    switch seg {
                    case .same: out.append(cur); cur = Line()
                    case .inserted: push(.inserted(newlineMark)); out.append(cur); cur = Line()
                    case .removed: push(.removed(newlineMark))
                    }
                }
                if !part.isEmpty {
                    let t = String(part)
                    switch seg { case .same: push(.same(t)); case .inserted: push(.inserted(t)); case .removed: push(.removed(t)) }
                }
            }
        }
        out.append(cur)
        return out
    }

    /// Only the verses that changed, `context` verses around each, « ⋯ » between.
    /// A short text (up to `showAllUpTo` verses) is shown whole.
    static func focus(_ lines: [Line], context: Int = 1, showAllUpTo: Int = 4) -> [Focused] {
        if lines.count <= showAllUpTo || !lines.contains(where: \.changed) { return lines.map { .line($0) } }
        var keep = Set<Int>()
        for (i, l) in lines.enumerated() where l.changed {
            for k in max(0, i - context)...min(lines.count - 1, i + context) { keep.insert(k) }
        }
        var out: [Focused] = []
        for (i, l) in lines.enumerated() {
            if keep.contains(i) { out.append(.line(l)) }
            else if out.last != .gap { out.append(.gap) }
        }
        return out
    }

    static func hasChange(_ old: String, _ new: String) -> Bool { !compute(old, new).allSatisfy(\.isSame) }

    // MARK: rendering

    /// The diff as one attributed run: removed words struck through in rose,
    /// inserted words in the author's colour, the rest as is; focused on the
    /// verses that changed unless `focused` is false.
    static func attributed(_ old: String, _ new: String, author: Color, base: Color = .white.opacity(0.92), focused: Bool = true) -> AttributedString {
        let ls = lines(compute(old, new))
        let items = focused ? focus(ls) : ls.map { .line($0) }
        var result = AttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 { result.append(AttributedString("\n")) }
            switch item {
            case .gap:
                var g = AttributedString("⋯"); g.foregroundColor = Theme.inkFaint
                result.append(g)
            case .line(let line):
                for seg in line.segments {
                    var s = AttributedString(seg.text)
                    switch seg {
                    case .same: s.foregroundColor = base
                    case .removed: s.foregroundColor = Theme.rose.opacity(0.9); s.strikethroughStyle = .single
                    case .inserted: s.foregroundColor = author; s.font = .callout.weight(.semibold)
                    }
                    result.append(s)
                }
            }
        }
        return result
    }
}
