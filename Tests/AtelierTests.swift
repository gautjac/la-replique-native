import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class AtelierTests: XCTestCase {

    private func makePlay(_ json: String) throws -> (ModelContainer, ModelContext, Play) {
        let schema = Schema([Play.self, Character.self, Element.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let play = PlayFormat.makePlay(from: try PlayFormat.decode(Data(json.utf8)), into: ctx)
        return (container, ctx, play)
    }

    private let sample = """
    { "lang":"fr","elements":[
      {"type":"scene","label":"SCÈNE 1","setting":"Cuisine"},
      {"type":"stage","text":"On frappe."},
      {"type":"cue","character":"BRUNO","parenthetical":"sec","text":"Ouvre."},
      {"type":"cue","character":"ALICE","text":"Non."}
    ] }
    """

    func testScriptTextFormatsCuesAndStage() throws {
        let (c, _, play) = try makePlay(sample); _ = c
        let text = Atelier.scriptText(play.elementList, play: play)
        XCTAssertTrue(text.contains("SCÈNE 1"))
        XCTAssertTrue(text.contains("BRUNO, sec"))
        XCTAssertTrue(text.contains("Ouvre."))
        XCTAssertTrue(text.contains("    On frappe.")) // stage indented
    }

    func testBuildBundleCollectsTranslatableText() throws {
        let (c, _, play) = try makePlay(sample); _ = c
        let keys = Translate.buildBundle(play).map(\.k)
        XCTAssertTrue(keys.contains("title"))
        XCTAssertTrue(keys.contains { $0.hasPrefix("cue:") })
        XCTAssertTrue(keys.contains { $0.hasPrefix("stage:") })
        XCTAssertFalse(keys.contains { $0.hasPrefix("act:") }) // act labels aren't translated
    }

    func testMakeTranslatedPlayRelabelsAndLinks() throws {
        let (c, ctx, play) = try makePlay(sample); _ = c
        let items = Translate.buildBundle(play).map { BundleItem(k: $0.k, t: $0.t.uppercased()) }
        let np = Translate.makeTranslatedPlay(play, to: .en, items: items, context: ctx)
        XCTAssertEqual(np.lang, .en)
        let scene = np.elementList.first { $0.kind == .scene }!
        XCTAssertEqual(scene.label, "SCENE 1")           // relabeled to target language
        let cue = np.elementList.first { $0.kind == .cue }!
        XCTAssertEqual(cue.text, "OUVRE.")               // translated
        XCTAssertNotNil(np.character(id: cue.characterID)) // speaker relinked
        XCTAssertTrue(np.title.hasSuffix("(EN)"))
    }

    func testResultStructsDecode() throws {
        let relance = try JSONDecoder().decode(RelanceRes.self, from: Data(#"{"line":"Va-t'en.","parenthetical":"sec"}"#.utf8))
        XCTAssertEqual(relance.line, "Va-t'en.")
        let dram = try JSONDecoder().decode(DramaturgieRes.self, from: Data(#"{"read":"ok","points":[{"kind":"tension","text":"x"}]}"#.utf8))
        XCTAssertEqual(dram.points.first?.kind, "tension")
        let trad = try JSONDecoder().decode(TraduireRes.self, from: Data(#"{"items":[{"k":"title","t":"The Door"}]}"#.utf8))
        XCTAssertEqual(trad.items.first?.t, "The Door")
    }
}
