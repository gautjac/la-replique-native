import XCTest
@testable import LaReplique

final class WordDiffTests: XCTestCase {
    private func flat(_ segs: [WordDiff.Segment]) -> [String] {
        segs.map { switch $0 { case .same(let t): return "=" + t; case .removed(let t): return "-" + t; case .inserted(let t): return "+" + t } }
    }
    private func flat(_ items: [WordDiff.Focused]) -> [String] {
        items.map { switch $0 { case .gap: return "⋯"; case .line(let l): return flat(l.segments).joined() } }
    }
    private func focused(_ a: String, _ b: String) -> [String] { flat(WordDiff.focus(WordDiff.lines(WordDiff.compute(a, b)))) }

    /// Shared with the web's wordDiff.test.ts.
    func testVectors() {
        XCTAssertEqual(flat(WordDiff.compute("Les plus bavards sont silencieux…", "Les plus bavards sont muets…")),
                       ["=Les plus bavards sont ", "-silencieux…", "+muets…"])
        XCTAssertEqual(flat(WordDiff.compute("Un deux trois", "Un deux trois")), ["=Un deux trois"])
        XCTAssertEqual(flat(WordDiff.compute("", "Bonjour")), ["+Bonjour"])
        XCTAssertEqual(flat(WordDiff.compute("Bonjour", "")), ["-Bonjour"])
        XCTAssertEqual(flat(WordDiff.compute("a b c", "a X b c")), ["=a ", "+X ", "=b c"])
        XCTAssertEqual(flat(WordDiff.compute("Ouvre la porte.", "Ferme la fenêtre.")), ["-Ouvre", "+Ferme", "= la ", "-porte.", "+fenêtre."])
        XCTAssertEqual(flat(WordDiff.compute("Ligne un\nLigne deux", "Ligne un\nLigne trois")), ["=Ligne un\nLigne ", "-deux", "+trois"])
    }

    /// Shared with the web too: verses, newline marks, focus.
    func testLineVectors() {
        XCTAssertEqual(focused("L1\nL2\nL3\nL4\nL5\nL6", "L1\nL2\nL3\nL4\nL5\nL6 changé"), ["⋯", "=L5", "=L6+ changé"])
        XCTAssertEqual(focused("A\nB", "A\n\nB"), ["=A", "+↵", "=B"])
        XCTAssertEqual(focused("A\nB", "A B"), ["=A-↵+ =B"])
        XCTAssertEqual(focused("L1\nL2\nL3\nL4\nL5\nL6\nL7\nL8", "L1\nL2 x\nL3\nL4\nL5\nL6\nL7\nL8 y"),
                       ["=L1", "=L2+ x", "=L3", "⋯", "=L7", "=L8+ y"])
        XCTAssertEqual(focused("L1\nL2\nL3\nL4\nL5\nL6", "L1\nL2\nL3\nL4\nL5\nL6"), ["=L1", "=L2", "=L3", "=L4", "=L5", "=L6"], "no change: shown whole")
    }

    func testEmptyBothIsEmpty() { XCTAssertEqual(WordDiff.compute("", ""), []) }

    func testHasChange() {
        XCTAssertTrue(WordDiff.hasChange("a", "b"))
        XCTAssertFalse(WordDiff.hasChange("même", "même"))
    }

    func testRoundTrip() {
        let a = "C'est moi Maggie, la Star de l'île…", b = "C'est moi Maggie, la vraie Star de l'île !"
        let segs = WordDiff.compute(a, b)
        XCTAssertEqual(segs.filter { if case .inserted = $0 { return false }; return true }.map(\.text).joined(), a)
        XCTAssertEqual(segs.filter { if case .removed = $0 { return false }; return true }.map(\.text).joined(), b)
    }
}
