import XCTest
@testable import LaReplique

final class WordDiffTests: XCTestCase {
    private func flat(_ segs: [WordDiff.Segment]) -> [String] {
        segs.map { switch $0 { case .same(let t): return "=" + t; case .removed(let t): return "-" + t; case .inserted(let t): return "+" + t } }
    }

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

    func testEmptyBothIsEmpty() { XCTAssertEqual(WordDiff.compute("", ""), []) }

    func testRoundTrip() {
        let a = "C'est moi Maggie, la Star de l'île…", b = "C'est moi Maggie, la vraie Star de l'île !"
        let segs = WordDiff.compute(a, b)
        XCTAssertEqual(segs.filter { if case .inserted = $0 { return false }; return true }.map(\.text).joined(), a)
        XCTAssertEqual(segs.filter { if case .removed = $0 { return false }; return true }.map(\.text).joined(), b)
    }
}
