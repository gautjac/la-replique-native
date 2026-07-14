import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class EditingTests: XCTestCase {

    private func makePlay(_ json: String) throws -> (ModelContainer, ModelContext, Play) {
        let schema = Schema([Play.self, Character.self, Element.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let doc = try PlayFormat.decode(Data(json.utf8))
        let play = PlayFormat.makePlay(from: doc, into: ctx)
        return (container, ctx, play)
    }

    private let twoHander = """
    { "lang":"fr","characters":[{"name":"BRUNO"},{"name":"ALICE"}],
      "elements":[
        {"type":"scene","label":"SCÈNE 1"},
        {"type":"cue","character":"BRUNO","text":"Un."},
        {"type":"cue","character":"ALICE","text":"Deux."},
        {"type":"cue","character":"BRUNO","text":"Trois."}
      ] }
    """

    func testCycleKind() {
        XCTAssertEqual(Editing.cycleKind(.cue), .stage)
        XCTAssertEqual(Editing.cycleKind(.stage), .scene)
        XCTAssertEqual(Editing.cycleKind(.action), .cue)
    }

    func testInsertInheritsLastSpeakerAndPosition() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        let firstCue = play.elementList.first { $0.kind == .cue }!
        let new = Editing.insert(.cue, after: firstCue, play: play, context: ctx)
        let arr = play.elementList
        let idx = arr.firstIndex { $0.id == new.id }!
        XCTAssertEqual(arr[idx - 1].id, firstCue.id)       // right after
        XCTAssertNotNil(play.character(id: new.characterID)) // linked to a real speaker
    }

    func testSuggestSpeakerPrefix() throws {
        let (c, _, play) = try makePlay(twoHander); _ = c
        // Unique prefix → that character.
        XCTAssertEqual(Editing.suggestSpeaker(play, prefix: "al")?.name, "ALICE")
        XCTAssertEqual(Editing.suggestSpeaker(play, prefix: "BRU")?.name, "BRUNO")
        // Case-insensitive, full name still matches.
        XCTAssertEqual(Editing.suggestSpeaker(play, prefix: "alice")?.name, "ALICE")
        // No match / empty → nil.
        XCTAssertNil(Editing.suggestSpeaker(play, prefix: "z"))
        XCTAssertNil(Editing.suggestSpeaker(play, prefix: ""))
    }

    func testAlternateSpeakerFlips() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        let brunoCue = play.elementList.first { $0.kind == .cue }!
        let other = Editing.alternateSpeaker(play, after: brunoCue)
        let alice = play.characterList.first { $0.name == "ALICE" }!
        XCTAssertEqual(other, alice.id.uuidString)
    }

    func testConvertCarriesText() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        let cue = play.elementList.first { $0.kind == .cue }!
        let saved = cue.text
        Editing.convert(cue, to: .stage, play: play, context: ctx)
        XCTAssertEqual(cue.kind, .stage)
        XCTAssertEqual(cue.text, saved)
        Editing.convert(cue, to: .cue, play: play, context: ctx)
        XCTAssertEqual(cue.kind, .cue)
        XCTAssertNotNil(cue.characterID) // reassigned a speaker
    }

    func testTypeAhead() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        // fresh empty cue
        let cue = Editing.insert(.cue, after: play.elementList.last, play: play, context: ctx)
        // space + existing name → switch, clears text
        cue.text = "ALICE"
        XCTAssertTrue(Editing.typeAhead(cue, token: "ALICE", allowCreate: false, play: play, context: ctx))
        XCTAssertEqual(play.character(id: cue.characterID)?.name, "ALICE")
        XCTAssertEqual(cue.text, "")
        // colon + new name → create
        XCTAssertTrue(Editing.typeAhead(cue, token: "MARIE", allowCreate: true, play: play, context: ctx))
        XCTAssertEqual(play.character(id: cue.characterID)?.name, "MARIE")
        // space + unknown → no-op
        XCTAssertFalse(Editing.typeAhead(cue, token: "Bonjour", allowCreate: false, play: play, context: ctx))
    }

    func testMoveSceneBlockCarriesItsBody() throws {
        let (c, ctx, play) = try makePlay("""
        { "lang":"fr","elements":[
          {"type":"scene","label":"SCÈNE 1"},{"type":"cue","character":"A","text":"un"},
          {"type":"scene","label":"SCÈNE 2"},{"type":"cue","character":"B","text":"deux"}
        ] }
        """); _ = c
        let (_, blocks) = Editing.decompose(play)
        let scene2 = blocks[1]                 // SCÈNE 2 block
        Editing.moveBlock(play, blockID: scene2.id, dir: -1)
        let labels = play.elementList.compactMap { $0.kind == .scene ? $0.label : nil }
        XCTAssertEqual(labels, ["SCÈNE 2", "SCÈNE 1"])
        // the cue "deux" moved with its scene
        let arr = play.elementList
        let s2 = arr.firstIndex { $0.label == "SCÈNE 2" }!
        XCTAssertEqual(arr[s2 + 1].text, "deux")
    }

    func testAddSceneAndRemoveCharacterKeepsLines() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        let added = Editing.addSceneAfter(play, blockID: nil, context: ctx)
        XCTAssertEqual(added.kind, .scene)
        XCTAssertEqual(play.elementList.last?.id, added.id)

        let before = play.elementList.filter { $0.kind == .cue }.count
        let bruno = play.characterList.first { $0.name == "BRUNO" }!
        Editing.removeCharacter(play, bruno, context: ctx)
        let after = play.elementList.filter { $0.kind == .cue }.count
        XCTAssertEqual(after, before)   // no lines lost
        XCTAssertFalse(play.characterList.contains { $0.name == "BRUNO" })
        XCTAssertTrue(play.elementList.contains { $0.kind == .cue && $0.characterID == nil })
    }

    func testRemoveReturnsPrevious() throws {
        let (c, ctx, play) = try makePlay(twoHander); _ = c
        let arr = play.elementList
        let target = arr[2]
        let prev = Editing.remove(target, play: play, context: ctx)
        XCTAssertEqual(prev?.id, arr[1].id)
        XCTAssertFalse(play.elementList.contains { $0.id == target.id })
        // order stays contiguous
        XCTAssertEqual(play.elementList.map(\.order), Array(0..<play.elementList.count))
    }
}
