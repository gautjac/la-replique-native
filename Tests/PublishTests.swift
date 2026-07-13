import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class PublishTests: XCTestCase {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Play.self, Character.self, Element.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return (container, ModelContext(container))
    }

    func testShareIDIsURLSafeAndUnique() throws {
        var seen = Set<String>()
        for _ in 0..<500 {
            let id = Publish.newShareID()
            XCTAssertFalse(id.isEmpty)
            // base64url alphabet only — no +, /, =, or whitespace
            let allowed = CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            XCTAssertNil(id.rangeOfCharacter(from: allowed.inverted),
                         "share id has non-URL-safe characters: \(id)")
            XCTAssertEqual(id, id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                           "share id should need no percent-encoding")
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, 500, "share ids should be unique")
    }

    func testWebURLMatchesViewerRoute() {
        let url = Publish.webURL(for: "abc-123_XY")
        XCTAssertEqual(url.absoluteString, "https://la-replique.netlify.app/lire/abc-123_XY")
    }

    /// The published payload is exactly the portable `la-replique/1` doc the web
    /// viewer parses — round-trips through decode without loss.
    func testPublishedJSONIsValidLaRepliqueDoc() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let play = Play(title: "La porte", lang: .fr)
        ctx.insert(play)
        let alice = Character(name: "ALICE", colorHex: "#4f7cff", order: 0); alice.play = play; ctx.insert(alice)
        let cue = Element(kind: .cue, order: 0); cue.characterID = alice.id.uuidString
        cue.text = "Ça veut rien dire."; cue.play = play; ctx.insert(cue)

        let data = try PlayFormat.aiJSON(from: play)
        let doc = try PlayFormat.decode(data)

        XCTAssertEqual(doc.format, "la-replique/1")
        XCTAssertEqual(doc.title, "La porte")
        XCTAssertEqual(doc.elements.first?.type, "cue")
        // The web viewer reads the speaker by NAME, not id.
        XCTAssertEqual(doc.elements.first?.character, "ALICE")
        XCTAssertEqual(doc.elements.first?.text, "Ça veut rien dire.")
    }
}
