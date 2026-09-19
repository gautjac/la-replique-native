import XCTest
import SwiftData
@testable import LaReplique

/// Mirrors the web viewer's `src/lire/comments.test.ts` — the two surfaces must
/// thread, resolve, hide and detach notes identically.
@MainActor
final class NotesTests: XCTestCase {
    private var clock = 0.0
    private func c(_ id: String, el: String = "e1", parent: String? = nil, resolved: Bool = false,
                   creator: String = "_zoe", at: Double? = nil) -> PlayComment {
        clock += 1
        return PlayComment(id: id, shareID: "s", elementID: el, quote: nil, body: "note", authorName: "Zoé",
                           parentID: parent, resolved: resolved, createdAt: Date(timeIntervalSince1970: at ?? clock), creator: creator)
    }
    private func meta(resolved: [String] = [], hidden: [String] = []) -> NotesMeta {
        NotesMeta(commentsOpen: true, resolved: resolved, hidden: hidden, owner: "_owner")
    }

    func testGroupsRepliesUnderRootOldestFirst() {
        let t = Notes.threads([c("r2", parent: "a"), c("a"), c("r1", parent: "a", at: 0)], meta: meta(), elementIDs: ["e1"])
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].root.id, "a")
        XCTAssertEqual(t[0].replies.map(\.id), ["r1", "r2"])
    }

    func testResolvedByAuthorOrOwner() {
        let t = Notes.threads([c("a", resolved: true), c("b"), c("d")], meta: meta(resolved: ["b"]), elementIDs: ["e1"])
        XCTAssertEqual(t.map(\.resolved), [true, true, false])
    }

    func testHiddenReplyVanishesAndHiddenRootTakesItsReplies() {
        let t = Notes.threads([c("a"), c("ra", parent: "a"), c("b"), c("rb1", parent: "b"), c("rb2", parent: "b")],
                              meta: meta(hidden: ["a", "rb1"]), elementIDs: ["e1"])
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].root.id, "b")
        XCTAssertEqual(t[0].replies.map(\.id), ["rb2"])
    }

    func testOrphanRepliesSurviveUnderTheEarliest() {
        let t = Notes.threads([c("r1", parent: "gone"), c("r2", parent: "gone")], meta: meta(resolved: ["gone"]), elementIDs: ["e1"])
        XCTAssertEqual(t.count, 1)
        XCTAssertTrue(t[0].rootDeleted)
        XCTAssertEqual(t[0].root.id, "r1")
        XCTAssertEqual(t[0].replies.map(\.id), ["r2"])
        XCTAssertEqual(t[0].key, "gone")
        XCTAssertTrue(t[0].resolved)
    }

    func testDetachedWhenLineIsGoneButNeverGeneralNotes() {
        let t = Notes.threads([c("a", el: "deleted"), c("g", el: Notes.general), c("k")], meta: meta(), elementIDs: ["e1"])
        XCTAssertEqual(t.map(\.detached), [true, false, false])
        XCTAssertTrue(Notes.threads(t, for: "deleted").isEmpty)
        XCTAssertEqual(Notes.threads(t, for: "e1").map(\.root.id), ["k"])
        XCTAssertEqual(Notes.threads(t, for: Notes.general).map(\.root.id), ["g"])
    }

    func testCountsAndMarginBadges() {
        let t = Notes.threads([c("a", resolved: true), c("b"), c("b2"), c("d", el: "x")], meta: meta(), elementIDs: ["e1"])
        let n = Notes.counts(t)
        XCTAssertEqual(n.open, 3); XCTAssertEqual(n.resolved, 1); XCTAssertEqual(n.detached, 1)
        XCTAssertEqual(Notes.openCounts(t), ["e1": 2])   // resolved and detached threads earn no badge
    }

    func testValidation() {
        XCTAssertEqual(Notes.validBody("  salut \r\n toi "), .success("salut \n toi"))
        XCTAssertEqual(Notes.validBody(" \n "), .failure(.empty))
        XCTAssertEqual(Notes.validBody(String(repeating: "x", count: Notes.maxBody + 1)), .failure(.tooLong))
        XCTAssertEqual(Notes.validName("  Zoé   LeBlanc "), .success("Zoé LeBlanc"))
        XCTAssertEqual(Notes.validName(""), .failure(.empty))
        XCTAssertEqual(Notes.validName(String(repeating: "n", count: 41)), .failure(.tooLong))
    }

    func testRights() {
        let m = meta()
        XCTAssertEqual(Notes.rights(viewer: "_zoe", meta: m, c("a")), .init(remove: true, hide: false, resolve: true))
        XCTAssertEqual(Notes.rights(viewer: "_owner", meta: m, c("a")), .init(remove: false, hide: true, resolve: true))
        XCTAssertEqual(Notes.rights(viewer: "_bob", meta: m, c("a")), .init(remove: false, hide: false, resolve: false))
        XCTAssertEqual(Notes.rights(viewer: nil, meta: m, c("a")), .init(remove: false, hide: false, resolve: false))
        XCTAssertFalse(Notes.rights(viewer: "_zoe", meta: m, c("r", parent: "a")).resolve)
    }

    func testReopenNeedsEveryFlagClearable() {
        let byAuthor = Notes.threads([c("a", resolved: true)], meta: meta(), elementIDs: ["e1"])[0]
        XCTAssertTrue(Notes.canReopen(byAuthor, viewer: "_zoe", meta: meta()))
        XCTAssertFalse(Notes.canReopen(byAuthor, viewer: "_owner", meta: meta()), "the owner cannot edit someone else's record")
        let byOwner = Notes.threads([c("b")], meta: meta(resolved: ["b"]), elementIDs: ["e1"])[0]
        XCTAssertTrue(Notes.canReopen(byOwner, viewer: "_owner", meta: meta(resolved: ["b"])))
        XCTAssertFalse(Notes.canReopen(byOwner, viewer: "_zoe", meta: meta(resolved: ["b"])))
    }

    func testUnreadCountsOthersNotesSinceLastSeen() {
        let seen = Date(timeIntervalSince1970: 100)
        let list = [c("old", at: 50), c("new", at: 150), c("mine", creator: "_me", at: 160), c("hid", at: 170)]
        XCTAssertEqual(Notes.unread(list, meta: meta(hidden: ["hid"]), since: seen, me: "_me"), 1)
        XCTAssertEqual(Notes.unread(list, meta: meta(), since: nil, me: "_me"), 3)
    }

    // MARK: anchors survive publish and restore

    private func makePlay() throws -> (ModelContainer, ModelContext, Play) {
        let schema = Schema([Play.self, Character.self, Element.self, Version.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let doc = try PlayFormat.decode(Data("""
        { "lang":"fr","characters":[{"name":"BRUNO"}],
          "elements":[{"type":"scene","label":"SCÈNE 1"},{"type":"cue","character":"BRUNO","text":"Un."},{"type":"cue","character":"BRUNO","text":"Deux."}] }
        """.utf8))
        return (container, ctx, PlayFormat.makePlay(from: doc, into: ctx))
    }

    func testPublishedDocCarriesElementIDsButTheAIExportDoesNot() throws {
        let (c, _, play) = try makePlay(); _ = c
        let published = PlayFormat.aiDoc(from: play, withElementIDs: true)
        XCTAssertEqual(published.elements.map(\.id), play.elementList.map { Optional($0.id.uuidString) })
        XCTAssertTrue(PlayFormat.aiDoc(from: play).elements.allSatisfy { $0.id == nil })
    }

    func testRestoringAVersionKeepsElementIDsSoNotesStayAttached() throws {
        let (c, ctx, play) = try makePlay(); _ = c
        let before = play.elementList.map(\.id)
        Versions.save(play, name: "v1", context: ctx)
        let v = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Version>()).first)
        play.elementList[1].text = "Réécrit."
        Versions.restore(v, into: play, context: ctx)
        XCTAssertEqual(play.elementList.map(\.id), before)
        XCTAssertEqual(play.elementList[1].text, "Un.")
    }

    func testImportingADocMintsFreshIDs() throws {
        let (c, ctx, play) = try makePlay(); _ = c
        let doc = PlayFormat.aiDoc(from: play, withElementIDs: true)
        let copy = PlayFormat.makePlay(from: doc, into: ctx)
        XCTAssertTrue(Set(copy.elementList.map(\.id)).isDisjoint(with: Set(play.elementList.map(\.id))))
    }
}
