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
