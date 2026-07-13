import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class StatsTests: XCTestCase {

    private func makePlay(_ json: String) throws -> (ModelContainer, ModelContext, Play) {
        let schema = Schema([Play.self, Character.self, Element.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let play = PlayFormat.makePlay(from: try PlayFormat.decode(Data(json.utf8)), into: ctx)
        return (container, ctx, play)
    }

    // scene1: ALICE, BRUNO · scene2: CAROL
    private let fixture = """
    { "lang":"fr","elements":[
      {"type":"scene","label":"SCÈNE 1"},
      {"type":"cue","character":"ALICE","text":"un deux"},
      {"type":"cue","character":"BRUNO","text":"trois"},
      {"type":"scene","label":"SCÈNE 2"},
      {"type":"cue","character":"CAROL","text":"quatre"}
    ] }
    """

    func testPresenceGrid() throws {
        let (c, _, play) = try makePlay(fixture); _ = c
        let scenes = Stats.scenes(play)
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].speakerIDs.count, 2)
        XCTAssertEqual(scenes[1].speakerIDs.count, 1)
    }

    func testCastStats() throws {
        let (c, _, play) = try makePlay(fixture); _ = c
        let (per, totals) = Stats.castStats(play)
        XCTAssertEqual(totals.totalLines, 3)
        XCTAssertEqual(totals.sceneCount, 2)
        let alice = per.first { $0.character.name == "ALICE" }!
        XCTAssertEqual(alice.lines, 1)
        XCTAssertEqual(alice.words, 2)      // "un deux"
        XCTAssertEqual(alice.scenes, 1)
    }

    func testThroughLines() throws {
        let (c, _, play) = try makePlay(fixture); _ = c
        let (labels, lines) = Stats.throughLines(play)
        XCTAssertEqual(labels.count, 2)
        let alice = lines.first { $0.character.name == "ALICE" }!
        let carol = lines.first { $0.character.name == "CAROL" }!
        XCTAssertEqual(alice.perScene, [1, 0])
        XCTAssertEqual(carol.perScene, [0, 1])
    }

    func testDoubling() throws {
        let (c, _, play) = try makePlay(fixture); _ = c
        let groups = Stats.doubling(play)
        let byName: (String) -> String = { id in play.character(id: id)?.name ?? "?" }
        let named = groups.map { $0.map(byName).sorted() }
        // ALICE & BRUNO share scene 1 → different groups; CAROL free to double.
        XCTAssertEqual(groups.count, 2)
        let aliceGroup = named.first { $0.contains("ALICE") }!
        XCTAssertFalse(aliceGroup.contains("BRUNO"))
    }

    func testRuntimeFormatting() {
        XCTAssertTrue(Stats.formatRuntime(0.2, .fr).contains("moins"))
        XCTAssertEqual(Stats.formatRuntime(95, .fr), "~1 h 35")
    }
}
