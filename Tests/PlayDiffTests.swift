import XCTest
@testable import LaReplique

final class PlayDiffTests: XCTestCase {
    private func el(_ id: String, _ text: String, type: String = "cue", who: String = "A") -> ElDoc {
        var d = ElDoc(type: type, text: text, character: who); d.id = id; return d
    }

    /// Shared with the web's playDiff.test.ts.
    func testVectors() {
        let a = [el("1", "Un."), el("2", "Deux."), el("3", "Trois."), el("4", "Quatre.")]
        let b = [el("1", "Un."), el("3", "Trois."), el("2", "Deux, changé."), el("5", "Cinq.")]
        let rows = PlayDiff.compare(a, b)
        let kinds: [String] = rows.map {
            switch $0 { case .same: return "same"; case .added: return "added"; case .removed: return "removed"; case .changed: return "changed"; case .moved: return "moved" }
        }
        XCTAssertEqual(kinds, ["same", "moved", "changed", "removed", "added"])
        let s = PlayDiff.summary(rows)
        XCTAssertEqual([s.added, s.removed, s.changed, s.moved], [1, 1, 1, 1])
    }

    func testIdenticalIsAllSame() {
        let a = [el("1", "Un."), el("2", "Deux.")]
        XCTAssertFalse(PlayDiff.compare(a, a).contains(where: \.isChange))
    }

    func testEmptySides() {
        XCTAssertEqual(PlayDiff.summary(PlayDiff.compare([], [el("1", "x")])).added, 1)
        XCTAssertEqual(PlayDiff.summary(PlayDiff.compare([el("1", "x")], [])).removed, 1)
    }

    func testSpeakerChangeIsAChange() {
        let rows = PlayDiff.compare([el("1", "Un.", who: "A")], [el("1", "Un.", who: "B")])
        if case .changed = rows[0] {} else { XCTFail("expected changed, got \(rows)") }
    }
}
