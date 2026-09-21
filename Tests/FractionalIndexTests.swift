import XCTest
@testable import LaReplique

final class FractionalIndexTests: XCTestCase {
    /// Shared with the web's fractionalIndex.test.ts — both sides must mint the same keys.
    func testVectors() {
        XCTAssertEqual(FractionalIndex.between(nil, nil), "V")
        XCTAssertEqual(FractionalIndex.between("V", nil), "V00G")
        XCTAssertEqual(FractionalIndex.between(nil, "V"), "Uzzk")
        XCTAssertEqual(FractionalIndex.between("V", "W"), "V7")
        XCTAssertEqual(FractionalIndex.between("V", "V7"), "V1")
        XCTAssertEqual(FractionalIndex.between("V1", "V2"), "V17")
        XCTAssertEqual(FractionalIndex.between("A", "z"), "G")
        XCTAssertEqual(FractionalIndex.between("Az", "B"), "Az7")
        XCTAssertEqual(FractionalIndex.between("A", "A001"), "A0007")
        XCTAssertEqual(FractionalIndex.spread(3), ["FV", "V1", "kV"])
    }

    func testAlwaysStrictlyBetweenAndNeverEndsInZero() {
        var rng = SystemRandomNumberGenerator()
        var keys = [FractionalIndex.between(nil, nil)]
        for _ in 0..<3000 {
            let i = Int.random(in: 0...keys.count, using: &rng)
            let a = i > 0 ? keys[i - 1] : nil, b = i < keys.count ? keys[i] : nil
            let k = FractionalIndex.between(a, b)
            if let a { XCTAssertLessThan(a, k) }
            if let b { XCTAssertLessThan(k, b) }
            XCTAssertNotEqual(k.last, "0")
            keys.insert(k, at: i)
        }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// The playwright's two real patterns must not blow keys up.
    func testWritingAtTheEndKeepsKeysShort() {
        var last = FractionalIndex.between(nil, nil)
        for _ in 0..<5000 { let k = FractionalIndex.between(last, nil); XCTAssertLessThan(last, k); last = k }
        XCTAssertLessThanOrEqual(last.count, 4)
        XCTAssertEqual(last, "VKoL")   // the web reaches the same value
    }

    func testWritingAStretchInTheMiddleStaysReasonable() {
        let next = "W"
        var prev = "V"
        for _ in 0..<300 { let k = FractionalIndex.between(prev, next); XCTAssertLessThan(prev, k); XCTAssertLessThan(k, next); prev = k }
        XCTAssertLessThanOrEqual(prev.count, 16, "300 lines written into one gap")
    }

    func testSpreadIsSortedUniqueAndLeavesRoom() {
        for n in [1, 2, 61, 1500, 20_000] {
            let keys = FractionalIndex.spread(n)
            XCTAssertEqual(keys.count, n)
            XCTAssertEqual(keys, keys.sorted())
            XCTAssertEqual(Set(keys).count, n)
            XCTAssertTrue(keys.allSatisfy { $0.last != "0" })
        }
        let k = FractionalIndex.spread(1500)
        XCTAssertLessThan(FractionalIndex.between(k[700], k[701]).count, 5)
    }
}
