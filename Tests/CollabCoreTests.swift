import XCTest
import SwiftData
@testable import LaReplique

@MainActor
final class CollabCoreTests: XCTestCase {
    private let scene = """
    { "lang":"fr","title":"La porte","characters":[{"name":"ALICE"},{"name":"BRUNO"}],
      "elements":[{"type":"scene","label":"SCÈNE 1"},
                  {"type":"cue","character":"BRUNO","text":"Un."},
                  {"type":"cue","character":"ALICE","text":"Deux."},
                  {"type":"cue","character":"BRUNO","text":"Trois."}] }
    """

    /// A shares, B (and C) join.
    private func table(_ extra: Int = 1) throws -> (FakeServer, Peer, [Peer]) {
        let server = FakeServer()
        let a = try Peer("A", server: server, json: scene)
        a.tick(); a.upload(); a.receive()
        let others = try (0..<extra).map { i -> Peer in let p = try Peer("B\(i)", server: server); p.join(); return p }
        return (server, a, others)
    }

    func testJoiningReproducesThePlayExactly_IdsIncluded() throws {
        let (_, a, o) = try table(); let b = o[0]
        XCTAssertEqual(b.fingerprint, a.fingerprint)
        XCTAssertEqual(b.texts, ["SCÈNE 1", "Un.", "Deux.", "Trois."])
        XCTAssertEqual(b.lines.map(\.id), a.lines.map(\.id), "notes anchor to element ids — they must match everywhere")
        b.tick()
        XCTAssertTrue(b.core.flushLocal().isEmpty, "joining must not echo anything back")
    }

    func testEditsToDifferentFieldsOfTheSameLineBothSurvive() throws {
        let (_, a, o) = try table(); let b = o[0]
        a.line("Deux.")!.parenthetical = "sèche"
        b.line("Deux.")!.text = "Deux, j'ai dit."
        settle([a, b])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        let l = a.line("Deux, j'ai dit.")
        XCTAssertEqual(l?.parenthetical, "sèche")
    }

    func testSameFieldIsLastWriterWinsAndEveryoneAgrees() throws {
        let (server, a, o) = try table(); let b = o[0]
        let id = a.line("Un.")!.id
        a.line("Un.")!.text = "Version A"; b.line("Un.")!.text = "Version B"
        a.tick(); b.tick(); a.upload(); b.upload()          // B reaches the server last
        settle([a, b])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.lines.first { $0.id == id }?.text, "Version B")
        XCTAssertEqual(server.docs[EntityRef(kind: .element, id: id.uuidString)]?[CollabField.text], "Version B")
    }

    func testTwoPeopleInsertingIntoTheSameGapBothLandInTheSameOrder() throws {
        let (_, a, o) = try table(2); let (b, c) = (o[0], o[1])
        a.insert(after: a.line("Un."), text: "de A")
        b.insert(after: b.line("Un."), text: "de B")     // identical order keys, minted independently
        settle([a, b, c])
        XCTAssertEqual(a.texts.count, 6)
        XCTAssertEqual(a.texts, b.texts); XCTAssertEqual(b.texts, c.texts)
        XCTAssertEqual(Set(a.texts[2...3]), ["de A", "de B"])
        // …and the tie doesn't jam the gap: a third insert between them still works.
        c.insert(after: c.lines[2], text: "de C")
        settle([a, b, c])
        XCTAssertEqual(a.texts, c.texts)
        XCTAssertEqual(a.texts[3], "de C")
    }

    func testDeleteBeatsAConcurrentEdit_NoResurrection() throws {
        let (server, a, o) = try table(); let b = o[0]
        let id = a.line("Deux.")!.id
        a.delete(a.line("Deux.")!)
        b.line("Deux.")!.text = "Deux, réécrit."
        a.tick(); a.upload()                                   // the delete lands first
        settle([a, b])
        XCTAssertEqual(a.texts, ["SCÈNE 1", "Un.", "Trois."])
        XCTAssertEqual(b.texts, a.texts)
        XCTAssertNil(server.docs[EntityRef(kind: .element, id: id.uuidString)])
    }

    /// Found by the fuzz (2026-09-21): I delete a line; before my next tick,
    /// someone's edit to that same line arrives. It must not come back — not for
    /// good (the original bug) and not even for an instant.
    func testALineIJustDeletedIsNotResurrectedByALateEdit() throws {
        let (server, a, o) = try table(); let b = o[0]
        let id = a.line("Deux.")!.id
        b.line("Deux.")!.text = "Deux, retouché."
        b.tick(); b.upload()
        a.delete(a.line("Deux.")!)              // not flushed yet…
        a.receive()                             // …when B's edit lands
        XCTAssertNil(a.lines.first { $0.id == id }, "must not flicker back")
        settle([a, b])
        XCTAssertEqual(a.texts, ["SCÈNE 1", "Un.", "Trois."])
        XCTAssertEqual(b.texts, a.texts)
        XCTAssertNil(server.docs[EntityRef(kind: .element, id: id.uuidString)])
    }

    func testMovingOneLineRewritesOnlyThatLinesKey() throws {
        let (_, a, o) = try table(); let b = o[0]
        a.move(a.line("Trois.")!, to: 1)
        let ops = a.core.flushLocal()
        XCTAssertEqual(ops.count, 1)
        guard case .patch(_, let set, _) = ops[0] else { return XCTFail("expected a patch") }
        XCTAssertEqual(Array(set.keys), [CollabField.orderKey])
        _ = b   // (kept alive)
    }

    func testAMoveReachesTheOthers() throws {
        let (_, a, o) = try table(); let b = o[0]
        a.move(a.line("Trois.")!, to: 1)
        settle([a, b])
        XCTAssertEqual(b.texts, ["SCÈNE 1", "Trois.", "Un.", "Deux."])
    }

    func testWritingAtTheEndSendsOnlyTheNewLine() throws {
        let (_, a, _) = try table()
        a.insert(after: a.lines.last, text: "Quatre.")
        let ops = a.core.flushLocal()
        XCTAssertEqual(ops.count, 1)
        if case .put = ops[0] {} else { XCTFail("expected one put, got \(ops)") }
    }

    func testFastTypingNeverSnapsBackToAnOlderValue() throws {
        let (_, a, o) = try table(); let b = o[0]
        let l = a.line("Un.")!
        var seenByA: [String] = []
        for t in ["U", "Un", "Un a", "Un au", "Un autre."] {
            l.text = t; a.tick(); a.upload()
            a.receive(1)                                         // echoes trickle in one at a time, late
            seenByA.append(l.text ?? "")
        }
        XCTAssertEqual(seenByA, ["U", "Un", "Un a", "Un au", "Un autre."])
        settle([a, b])
        XCTAssertEqual(b.line("Un autre.")?.id, l.id)
    }

    /// Jac's cursor jumped while typing (2026-09-22): the server's confirmation
    /// of the last tick's text arrived as a data change (its timestamp resolved),
    /// and the engine — having just flushed the newer text — took the older
    /// value for news and wrote it back over what was typed since.
    func testTypingBetweenTicksSurvivesTheEchoOfTheLastTick() throws {
        let (_, a, o) = try table(); let b = o[0]
        let l = a.line("Un.")!
        l.text = "Un a"; a.tick(); a.upload()                 // sent
        l.text = "Un au"                                      // typed since, not yet ticked
        var seen: [String] = []
        a.observe = { seen.append(l.text ?? "") }
        a.receive()                                           // the confirmation of "Un a" lands now
        XCTAssertEqual(l.text, "Un au")
        XCTAssertEqual(Set(seen), ["Un au"], "an echo of my own write must never undo what I typed since, not even for an instant: \(seen)")
        a.tick(); a.upload(); a.receive()
        XCTAssertEqual(l.text, "Un au")
        settle([a, b])
        XCTAssertEqual(b.line("Un au")?.id, l.id)
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }

    func testOfflineEditsMergeOnReconnect_EvenAcrossARelaunch() throws {
        let (_, a, o) = try table(); let b = o[0]
        b.online = false
        b.line("Trois.")!.text = "Trois, écrit dans le train."
        b.insert(after: b.lines.last, text: "Quatre, aussi hors ligne.")
        b.tick()
        b.line("Un.")!.parenthetical = "juste avant de fermer l'app"   // never even flushed
        b.relaunch()
        a.line("Deux.")!.text = "Deux, écrit pendant ce temps."
        a.insert(after: a.line("Un."), text: "Un et demi.")
        settle([a, b])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.texts, ["SCÈNE 1", "Un.", "Un et demi.", "Deux, écrit pendant ce temps.", "Trois, écrit dans le train.", "Quatre, aussi hors ligne."])
        XCTAssertEqual(a.line("Un.")?.parenthetical, "juste avant de fermer l'app")
    }

    func testCastAndTitleTravelToo() throws {
        let (_, a, o) = try table(); let b = o[0]
        a.play.title = "La porte (2e version)"
        let c = Editing.addCharacter(a.play, name: "CLAIRE", context: a.context)
        a.line("Deux.")!.characterID = c.id.uuidString        // ALICE's line → CLAIRE
        let bruno = b.play.characterList.first { $0.name == "BRUNO" }!
        Editing.removeCharacter(b.play, bruno, context: b.context)
        settle([a, b])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(b.play.title, "La porte (2e version)")
        XCTAssertEqual(Set(b.play.characterList.map(\.name)), ["ALICE", "CLAIRE"])
        XCTAssertEqual(b.play.character(id: b.line("Deux.")!.characterID)?.name, "CLAIRE")
        XCTAssertNil(a.line("Trois.")!.characterID, "BRUNO's lines stay, unassigned — same rule as the editor")
    }

    func testLongestIncreasingRun() {
        XCTAssertEqual(CollabCore.longestIncreasingRun(["a", "c", "b", "d"]).count, 3)
        // Strict: of two equal keys exactly one is kept (the later), the other is re-keyed.
        XCTAssertEqual(CollabCore.longestIncreasingRun(["a", nil, "b", "b", "c"]), [0, 3, 4])
        XCTAssertEqual(CollabCore.longestIncreasingRun([nil, nil]), [])
    }

    func testAFullLengthPlay_ShareIsFast_AndOneKeystrokeIsOneOp() throws {
        let server = FakeServer()
        let a = try Peer("A", server: server)
        var prev: Element?
        for i in 0..<1500 { prev = a.insert(after: prev, text: "Réplique \(i)", kind: i % 40 == 0 ? .scene : .cue) }
        let t0 = Date()
        let share = a.core.flushLocal()
        XCTAssertEqual(share.count, 1501)                                   // info + 1500 lines
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
        a.lines[700].text = "Une seule touche."
        let t1 = Date()
        let ops = a.core.flushLocal()
        XCTAssertLessThan(Date().timeIntervalSince(t1), 0.25, "this runs on a timer while you type")
        XCTAssertEqual(ops.count, 1)
    }

    /// Several writers, random edits / inserts / deletes / moves, random offline
    /// spells and late deliveries — everyone must end on the same play, which must
    /// be the server's. Seeds are fixed so a failure replays.
    func testFuzz_EveryoneConverges() throws {
        // `TEST_RUNNER_LR_FUZZ_SEEDS=200 xcodebuild test …` for a long soak.
        let extra = ProcessInfo.processInfo.environment["LR_FUZZ_SEEDS"].flatMap(UInt64.init) ?? 0
        for seed in [1, 7, 42, 1789, 2026] + (extra > 0 ? Array(100..<(100 + extra)) : []) as [UInt64] {
            var rng = Lcg(state: seed)
            let (server, a, o) = try table(2)
            let peers = [a] + o
            for step in 0..<220 {
                let p = peers.randomElement(using: &rng)!
                switch Int.random(in: 0..<11, using: &rng) {
                case 0...2: if let l = p.lines.randomElement(using: &rng) { l.text = "\(p.name)·\(step)" }
                case 3...4: p.insert(after: p.lines.randomElement(using: &rng), text: "nouvelle \(p.name)·\(step)")
                case 5: if p.lines.count > 3, let l = p.lines.randomElement(using: &rng) { p.delete(l) }
                case 6: if let l = p.lines.randomElement(using: &rng) { p.move(l, to: Int.random(in: 0...p.lines.count, using: &rng)) }
                case 7: p.online.toggle()
                case 8: if let l = p.lines.randomElement(using: &rng) { l.parenthetical = step % 3 == 0 ? nil : "jeu \(step)" }
                case 9: if Int.random(in: 0..<4, using: &rng) == 0 { p.tick(); p.relaunch() }
                default: break
                }
                if Bool.random(using: &rng) { p.tick() }
                if Bool.random(using: &rng) { p.upload() }
                if Bool.random(using: &rng) { p.receive(Int.random(in: 1...4, using: &rng)) }
            }
            settle(peers)
            for p in peers.dropFirst() { XCTAssertEqual(p.fingerprint, a.fingerprint, "seed \(seed): \(p.name) diverged from A") }
            let serverLines = server.docs.filter { $0.key.kind == .element }.count
            XCTAssertEqual(serverLines, a.lines.count, "seed \(seed): server and clients disagree on what exists")
            let keys = a.lines.compactMap { a.core.shadow[EntityRef(kind: .element, id: $0.id.uuidString)]?[CollabField.orderKey] }
            XCTAssertEqual(keys.count, a.lines.count)
            XCTAssertEqual(keys, keys.sorted(), "seed \(seed): local order must follow the agreed keys")
        }
    }
}
