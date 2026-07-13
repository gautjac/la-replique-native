import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class PlayFormatTests: XCTestCase {

    /// A fresh in-memory container. Retained by the caller for the test's duration
    /// (SwiftData traps on first use if the container is released early).
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Play.self, Character.self, Element.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return (container, ModelContext(container))
    }

    private func decode(_ json: String) throws -> PlayDoc {
        try PlayFormat.decode(Data(json.utf8))
    }

    func testImportLinksSpeakersAndPreservesFields() throws {
        let (container, ctx) = try makeContext()
        _ = container // keep alive
        let doc = try decode("""
        { "format":"la-replique/1","title":"La porte","lang":"fr",
          "characters":[{"name":"ALICE"},{"name":"BRUNO","note":"revenu"}],
          "elements":[
            {"type":"act","label":"ACTE I"},
            {"type":"scene","label":"SCÈNE 1","setting":"Cuisine"},
            {"type":"stage","text":"On frappe."},
            {"type":"cue","character":"BRUNO","parenthetical":"derrière la porte","text":"Je sais que t'es là."},
            {"type":"cue","character":"ALICE","text":"Ça veut rien dire."},
            {"type":"cue","character":"BRUNO","text":"Ouvre la porte."}
          ] }
        """)
        let play = PlayFormat.makePlay(from: doc, into: ctx)

        XCTAssertEqual(play.title, "La porte")
        XCTAssertEqual(play.characterList.map(\.name).sorted(), ["ALICE", "BRUNO"])
        let cues = play.elementList.filter { $0.kind == .cue }
        XCTAssertEqual(cues.count, 3)
        // every cue resolves to a real character
        for c in cues { XCTAssertNotNil(play.character(id: c.characterID)) }
        // both BRUNO cues share one character id
        let bruno = play.characterList.first { $0.name == "BRUNO" }!
        XCTAssertEqual(cues.filter { $0.characterID == bruno.id.uuidString }.count, 2)
        XCTAssertEqual(cues.first?.parenthetical, "derrière la porte")
        // scene setting kept, elements ordered
        XCTAssertEqual(play.elementList.count, 6)
        XCTAssertEqual(play.elementList.first?.kind, .act)
    }

    func testImportAutoCreatesCharactersFromCueNames() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let doc = try decode("""
        { "lang":"en","elements":[
            {"type":"cue","character":"NINA","text":"You're late."},
            {"type":"cue","character":"MARC","text":"I know."},
            {"type":"cue","character":"NINA","text":"Again."}
        ] }
        """)
        let play = PlayFormat.makePlay(from: doc, into: ctx)
        XCTAssertEqual(play.characterList.map(\.name).sorted(), ["MARC", "NINA"])
        let nina = play.characterList.first { $0.name == "NINA" }!
        let ninaCues = play.elementList.filter { $0.kind == .cue && $0.characterID == nina.id.uuidString }
        XCTAssertEqual(ninaCues.count, 2)
        XCTAssertEqual(play.lang, .en)
    }

    func testAiExportReferencesSpeakerByName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let doc = try decode("""
        { "lang":"fr","characters":[{"name":"ALICE","voiceId":"v1"}],
          "elements":[
            {"type":"scene","label":"SCÈNE 1","setting":"Ici","beat":"turn"},
            {"type":"cue","character":"ALICE","text":"Bonjour."}
          ] }
        """)
        let play = PlayFormat.makePlay(from: doc, into: ctx)
        let out = PlayFormat.aiDoc(from: play)

        let cue = out.elements.first { $0.type == "cue" }
        XCTAssertEqual(cue?.character, "ALICE")
        XCTAssertNil(cue?.characterId)
        let scene = out.elements.first { $0.type == "scene" }
        XCTAssertEqual(scene?.beat, "turn")
        XCTAssertEqual(scene?.setting, "Ici")
        XCTAssertEqual(out.characters?.first?.voiceId, "v1")
        XCTAssertEqual(out.format, "la-replique/1")
    }
}
