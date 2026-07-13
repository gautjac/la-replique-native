import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class VersionsTests: XCTestCase {

    private func make(_ json: String) throws -> (ModelContainer, ModelContext, Play) {
        let schema = Schema([Play.self, Character.self, Element.self, Version.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let play = PlayFormat.makePlay(from: try PlayFormat.decode(Data(json.utf8)), into: ctx)
        return (container, ctx, play)
    }

    private let sample = """
    { "lang":"fr","title":"La porte","elements":[
      {"type":"scene","label":"SCÈNE 1"},
      {"type":"cue","character":"BRUNO","text":"Ouvre."},
      {"type":"cue","character":"ALICE","text":"Non."}
    ] }
    """

    func testSaveThenRestoreReplacesContent() throws {
        let (container, ctx, play) = try make(sample); _ = container
        let originalCount = play.elementList.count       // 3
        Versions.save(play, name: "1er jet", context: ctx)

        // mutate: wipe all elements
        for e in play.elementList { Editing.remove(e, play: play, context: ctx) }
        XCTAssertEqual(play.elementList.count, 0)

        let versions = try ctx.fetch(FetchDescriptor<Version>())
        XCTAssertEqual(versions.count, 1)
        Versions.restore(versions[0], into: play, context: ctx)

        XCTAssertEqual(play.elementList.count, originalCount)
        XCTAssertEqual(play.title, "La porte")
        let cue = play.elementList.first { $0.kind == .cue }!
        XCTAssertNotNil(play.character(id: cue.characterID)) // speakers relinked after restore
    }

    func testPlainTextExport() throws {
        let (container, _, play) = try make(sample); _ = container
        let text = Exports.plainText(play)
        XCTAssertTrue(text.hasPrefix("LA PORTE"))
        XCTAssertTrue(text.contains("BRUNO"))
        XCTAssertTrue(text.contains("Ouvre."))
    }
}
