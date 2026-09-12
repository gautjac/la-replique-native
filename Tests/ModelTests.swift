import XCTest
@testable import LaReplique

@MainActor
final class ModelTests: XCTestCase {
    /// `touch()` is called on every keystroke; it must not rewrite `updatedAt`
    /// (and so re-sort the library) more than once a second.
    func testTouchCoalescesWithinASecond() {
        let play = Play(title: "T")
        let t0 = Date(timeIntervalSinceNow: -0.2)
        play.updatedAt = t0
        play.touch()
        XCTAssertEqual(play.updatedAt, t0, "a touch 200 ms after the last write must be a no-op")
    }

    func testTouchWritesAfterASecond() {
        let play = Play(title: "T")
        let old = Date(timeIntervalSinceNow: -5)
        play.updatedAt = old
        play.touch()
        XCTAssertGreaterThan(play.updatedAt, old)
    }

    func testTouchOverwritesAFutureTimestamp() {
        // Clock skew between synced devices can leave updatedAt in the future;
        // touch() must still bring it back to "now" rather than stall forever.
        let play = Play(title: "T")
        let future = Date(timeIntervalSinceNow: 3600)
        play.updatedAt = future
        play.touch()
        XCTAssertLessThan(play.updatedAt, future)
    }

    func testInterfaceLanguageResources() {
        XCTAssertNil(InterfaceLanguage.system.lproj)
        XCTAssertEqual(InterfaceLanguage.fr.lproj, "fr")
        XCTAssertEqual(InterfaceLanguage.en.lproj, "en")
        XCTAssertEqual(InterfaceLanguage.en.locale.identifier, "en")
    }
}
