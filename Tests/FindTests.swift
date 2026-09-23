import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class FindTests: XCTestCase {
    private func makePlay() throws -> (Play, ModelContext) {
        let schema = Schema([Play.self, Character.self, Element.self, Version.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let json = """
        { "lang":"fr","title":"La porte","characters":[{"name":"ALICE"}],
          "elements":[{"type":"scene","label":"SCÈNE 1 — L'île"},
                      {"type":"cue","character":"ALICE","text":"C'est moi Maggie, la Star de l'île… Une île, deux îles."},
                      {"type":"stage","text":"Un temps."},
                      {"type":"cue","character":"ALICE","text":"Ile ou pas ile."}] }
        """
        let play = PlayFormat.makePlay(from: try PlayFormat.decode(Data(json.utf8)), into: context)
        return (play, context)
    }

    func testFindsCaseAndAccentInsensitively_InReadingOrder() throws {
        let (play, _) = try makePlay()
        let m = FindState.find("ile", in: play)
        XCTAssertEqual(m.count, 6, "SCÈNE label (1) + Maggie's line (3) + last line (2)")
        XCTAssertEqual(m[0].field, .label)
        XCTAssertEqual(m.dropFirst().map(\.field), Array(repeating: .text, count: 5))
        // Offsets are Character offsets into the field's text, usable to select the hit.
        let line = play.elementList[1].text ?? ""
        let r = FindHit(id: m[1].id, field: .text, lower: m[1].lower, upper: m[1].upper, token: 1, select: true).range(in: line)!
        XCTAssertEqual(String(line[r]), "île")
    }

    func testEmptyQueryFindsNothing() throws {
        let (play, _) = try makePlay()
        XCTAssertTrue(FindState.find("", in: play).isEmpty)
        XCTAssertTrue(FindState.find("   ", in: play).isEmpty)
        XCTAssertTrue(FindState.find("zèbre", in: play).isEmpty)
    }

    func testNextAndPreviousWrapAround_AndSelectOnlyWhenStepping() throws {
        let (play, _) = try makePlay()
        let f = FindState()
        f.query = "île"
        f.rebuild(play, jump: true)
        XCTAssertEqual(f.index, 0)
        XCTAssertEqual(f.hit?.select, false, "typing lands on the first hit without stealing focus")
        f.next(play); XCTAssertEqual(f.index, 1); XCTAssertEqual(f.hit?.select, true)
        for _ in 0..<5 { f.next(play) }
        XCTAssertEqual(f.index, 0, "wraps after the last hit")
        f.previous(play); XCTAssertEqual(f.index, 5, "wraps before the first hit")
        let t1 = f.hit!.token; f.previous(play); f.next(play)
        XCTAssertGreaterThan(f.hit!.token, t1, "every step bumps the token, even back to the same hit")
    }

    func testRebuildKeepsThePositionWhenTheTextChangesElsewhere() throws {
        let (play, _) = try makePlay()
        let f = FindState()
        f.query = "île"; f.rebuild(play, jump: true); f.next(play); f.next(play)
        let at = f.matches[f.index!]
        play.elementList[3].text = "Ile ou pas ile, ni île."          // a new hit AFTER the current one
        f.rebuild(play, jump: false)
        XCTAssertEqual(f.matches[f.index!], at, "still on the same hit")
        XCTAssertEqual(f.matches.count, 7)
        f.close()
        XCTAssertNil(f.hit); XCTAssertTrue(f.matches.isEmpty); XCTAssertFalse(f.isPresented)
    }
}
