import SwiftUI

/// A word-level comparison of two texts — what the history and the version
/// comparison show instead of the whole line twice. Tokens are runs of
/// non-blanks and runs of blanks; the diff is a plain LCS (deterministic, no
/// heuristics) so the web twin `src/collab/wordDiff.ts` produces the same
/// segments on the same input (shared test vectors).
enum WordDiff {
    enum Segment: Equatable {
        case same(String), removed(String), inserted(String)
        var text: String { switch self { case .same(let s), .removed(let s), .inserted(let s): return s } }
    }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var blank: Bool?
        for ch in s {
            let b = ch.isWhitespace || ch.isNewline
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

    /// The diff as one attributed run: removed words struck through in rose,
    /// inserted words in the author's colour, the rest as is.
    static func attributed(_ old: String, _ new: String, author: Color, base: Color = .white.opacity(0.92)) -> AttributedString {
        var result = AttributedString()
        for seg in compute(old, new) {
            var s = AttributedString(seg.text)
            switch seg {
            case .same: s.foregroundColor = base
            case .removed: s.foregroundColor = Theme.rose.opacity(0.9); s.strikethroughStyle = .single
            case .inserted: s.foregroundColor = author; s.font = .callout.weight(.semibold)
            }
            result.append(s)
        }
        return result
    }
}
