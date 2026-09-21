import Foundation

/// Order keys for a list that several people edit at once.
///
/// Locally, elements keep their dense `order: Int`, renumbered on every insert —
/// fine for one writer, hopeless for two (every insert would rewrite every row
/// and collide). In a shared play each element instead carries a string key;
/// the list order is the keys' plain string order, and inserting between two
/// neighbours mints a key between theirs WITHOUT touching anyone else.
///
/// Keys are base-62 digit strings (`0-9A-Za-z`, which is also their ASCII order)
/// read as fractions: "V" = 0.V, "V5" = 0.V5. A key never ends in "0", so there
/// is always room before it. Mirrored by the web's `src/collab/fractionalIndex.ts`
/// — the two MUST mint identical keys (shared vectors in both test suites).
// NB: inside this module a bare `Character` is the play's @Model class — text
// characters are spelled `Swift.Character` here.
enum FractionalIndex {
    static let digits: [Swift.Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = 62
    nonisolated(unsafe) private static let value: [Swift.Character: Int] = Dictionary(uniqueKeysWithValues: digits.enumerated().map { ($1, $0) })

    /// Appending/prepending works on a fixed-width head so keys grow by a constant
    /// step instead of bisecting what's left (which would add a character every
    /// half-dozen lines — and writing at the end is what a playwright does all day).
    private static let headWidth = 4
    private static let step = 16
    /// When splitting a gap, land 1/8 of the way in rather than the middle: lines
    /// are usually written one after the other, each new one going after the last,
    /// and a low split leaves the remaining gap nearly intact (~30 inserts per
    /// character instead of ~6).
    private static let bias = 8

    /// A key strictly between `a` and `b`. nil = the open end on that side.
    static func between(_ a: String?, _ b: String?) -> String {
        switch (a.flatMap { $0.isEmpty ? nil : $0 }, b.flatMap { $0.isEmpty ? nil : $0 }) {
        case (nil, nil): return "V"
        case (let a?, nil): return after(a)
        case (nil, let b?): return before(b)
        case (let a?, let b?):
            precondition(a < b, "FractionalIndex.between needs a < b (got \(a) ≥ \(b))")
            return midpoint(Array(a), Array(b))
        }
    }

    /// `count` evenly spaced keys for a whole list at once (first share, rebalance).
    static func spread(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        var width = 2
        while pow(Double(base), Double(width)) < Double(count + 1) * 64 { width += 1 }
        let space = Int(pow(Double(base), Double(width)))
        let stride = space / (count + 1)
        return (1...count).map { encode($0 * stride, width: width) }
    }

    // MARK: - ends

    private static func head(_ key: String) -> Int {
        var n = 0
        let chars = Array(key.prefix(headWidth))
        for i in 0..<headWidth { n = n * base + (i < chars.count ? value[chars[i]] ?? 0 : 0) }
        return n
    }

    private static func after(_ a: String) -> String {
        let limit = Int(pow(Double(base), Double(headWidth)))
        let n = head(a) + step
        // Out of head room (≈ 900 000 appends): fall back to bisecting toward the end.
        return n < limit ? encode(n, width: headWidth) : midpoint(Array(a), nil)
    }

    private static func before(_ b: String) -> String {
        let n = head(b) - step
        return n > 0 ? encode(n, width: headWidth) : midpoint([], Array(b))
    }

    /// Fixed-width base-62, never ending in "0" (nudged up by one — still inside
    /// the step, so order is preserved).
    private static func encode(_ n: Int, width: Int) -> String {
        var n = n % base == 0 ? n + 1 : n
        var out = [Swift.Character](repeating: "0", count: width)
        for i in stride(from: width - 1, through: 0, by: -1) { out[i] = digits[n % base]; n /= base }
        return String(out)
    }

    // MARK: - between two keys

    /// `a` < `b` as fractions; `b` nil = 1.0. Neither ends in "0".
    private static func midpoint(_ a: [Swift.Character], _ b: [Swift.Character]?) -> String {
        if let b {
            // Shared prefix (padding `a` with zeros): keep it, recurse on the rest.
            var n = 0
            while n < b.count, (n < a.count ? a[n] : "0") == b[n] { n += 1 }
            if n > 0 { return String(b[0..<n]) + midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n))) }
        }
        let da = a.first.flatMap { value[$0] } ?? 0
        let db = b?.first.flatMap { value[$0] } ?? base
        if db - da > 1 {
            return String(digits[da + max(1, (db - da) / bias)])
        }
        // Adjacent first digits.
        if let b, b.count > 1 { return String(b[0]) }          // "X…" > "X" > a
        return String(digits[da]) + midpoint(Array(a.dropFirst()), nil)
    }
}
