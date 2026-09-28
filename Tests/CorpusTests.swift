import XCTest
import ClaudeKit
@testable import LaReplique

/// The craft corpus must ship inside the bundle and assemble into the same
/// block layout as the web function: shared cached core, per-op cached extras,
/// uncached task prompt.
final class CorpusTests: XCTestCase {

    private let ops = ["relance", "dramaturgie", "traduire", "retoucher", "voix", "etsi", "dramaturge"]

    func testManifestCoversTheSixAtelierOps() {
        XCTAssertEqual(Corpus.ops, ops.sorted())
        XCTAssertEqual(Corpus.manifest.core, ["sw-workflow/terms.md", "sw-dialogue/SKILL.md", "sw-scene-craft/SKILL.md", "sw-character-conflict/SKILL.md"])
        XCTAssertTrue(Corpus.manifest.source.repo.contains("screenwriting-skills"))
    }

    func testEveryVendoredFileIsInTheBundleAndCarriesItsFrontmatter() throws {
        let all = Set(Corpus.manifest.core + Corpus.manifest.ops.values.flatMap { $0 })
        XCTAssertGreaterThanOrEqual(all.count, 10)
        for rel in all {
            let text = try Corpus.file(rel)
            XCTAssertGreaterThan(text.count, 2000, rel)
            if rel.hasSuffix("SKILL.md") {
                let skill = rel.split(separator: "/").first.map(String.init) ?? ""
                XCTAssertTrue(text.hasPrefix("---\nname: \(skill)"), rel)
            }
        }
    }

    func testPreambleStatesTheRulesThatMatter() throws {
        let p = try Corpus.preamble()
        XCTAssertTrue(p.hasPrefix("# Craft reference for the Atelier"))
        XCTAssertTrue(p.contains("Never quote it"))
        XCTAssertTrue(p.contains("Never output Chinese"))
        XCTAssertTrue(p.contains("background knowledge only"))
    }

    func testCoreBlockIsIdenticalAcrossOpsAndCachedOneHour() throws {
        let first = try Corpus.system(op: "relance", task: "x")[0]
        XCTAssertEqual(first.cacheControl, ClaudeCacheControl(ttl: .oneHour))
        XCTAssertGreaterThan(first.text.count, 4000) // well above Opus 4.8's 1024-token cache minimum
        XCTAssertTrue(first.text.contains("<craft-reference file=\"sw-workflow/terms.md\">"))
        for op in ops {
            XCTAssertEqual(try Corpus.system(op: op, task: "task \(op)")[0], first, op)
        }
    }

    func testExtrasAreASecondCachedBlockAndTaskIsNeverCached() throws {
        for op in ops {
            let blocks = try Corpus.system(op: op, task: "TASK")
            let task = try XCTUnwrap(blocks.last)
            XCTAssertEqual(task.text, "TASK")
            XCTAssertNil(task.cacheControl)
            let extras = Corpus.manifest.ops[op] ?? []
            XCTAssertEqual(blocks.count, extras.isEmpty ? 2 : 3, op)
            if !extras.isEmpty {
                XCTAssertEqual(blocks[1].cacheControl, ClaudeCacheControl(ttl: .oneHour))
                for rel in extras { XCTAssertTrue(blocks[1].text.contains("<craft-reference file=\"\(rel)\">"), "\(op) ← \(rel)") }
            }
        }
        XCTAssertNil(try Corpus.extrasText(op: "traduire"))
        XCTAssertEqual(try Corpus.system(op: "relance", task: "t", ttl: .fiveMinutes)[0].cacheControl, ClaudeCacheControl(ttl: .fiveMinutes))
    }

    func testOpProfilesPointEachToolAtTheRightCraft() throws {
        XCTAssertTrue(try Corpus.files(for: "relance").contains("chekhov-dramaturgy/SKILL.md"))
        XCTAssertTrue(try Corpus.files(for: "dramaturgie").contains("sw-story-structure/SKILL.md"))
        XCTAssertTrue(try Corpus.files(for: "etsi").contains("sw-premise-theme/SKILL.md"))
        XCTAssertTrue(try Corpus.files(for: "voix").contains("sw-character-conflict/reference.md"))
        XCTAssertTrue(try Corpus.files(for: "dramaturge").contains("sw-premise-theme/SKILL.md"))
        XCTAssertThrowsError(try Corpus.files(for: "nope")) { XCTAssertEqual($0 as? Corpus.CorpusError, .unknownOp("nope")) }
        for op in ops {
            let chars = try Corpus.system(op: op, task: "").reduce(0) { $0 + $1.text.count }
            XCTAssertLessThan(chars, 100_000, op) // ≈ 1 token per char in this corpus
        }
    }
}

/// The tool list is part of the cache prefix: fixed content, fixed order.
final class AtelierToolsTests: XCTestCase {
    func testOneFixedToolListInStableOrder() {
        XCTAssertEqual(Atelier.tools.map(\.name), ["proposer_replique", "notes", "voix", "et_si", "retoucher", "traduction", "reponse"])
        for t in Atelier.tools { XCTAssertEqual(t.description, "Return the result.") }
    }
}

final class DramaturgeTests: XCTestCase {
    func testTrimHistoryTailStartsOnUserAndAlternates() {
        let h = (0..<30).map { DramaturgeTurn(role: $0 % 2 == 0 ? "user" : "assistant", text: "t\($0)") }
        let out = Atelier.trimHistory(h)
        XCTAssertLessThanOrEqual(out.count, Atelier.dramaturgeMaxTurns)
        XCTAssertEqual(out.first?.role, "user")
        XCTAssertEqual(out.last?.text, "t29")
        XCTAssertEqual(Atelier.trimHistory([DramaturgeTurn(role: "assistant", text: "a"), DramaturgeTurn(role: "user", text: "q"), DramaturgeTurn(role: "user", text: "r")]),
                       [DramaturgeTurn(role: "user", text: "q\n\nr")])
        XCTAssertEqual(Atelier.trimHistory([DramaturgeTurn(role: "system", text: "x"), DramaturgeTurn(role: "user", text: " ")]), [])
    }
    func testAnswerBlocksParagraphsAndBullets() {
        XCTAssertEqual(AnswerText.blocks("Un.\nDeux.\n\nTrois."), [.paragraph("Un. Deux."), .paragraph("Trois.")])
        XCTAssertEqual(AnswerText.blocks("Deux pistes :\n- couper\n- entrer\nVoilà."), [.paragraph("Deux pistes :"), .bullets(["couper", "entrer"]), .paragraph("Voilà.")])
        XCTAssertEqual(AnswerText.blocks(""), [])
    }
    /// The play rides in the cached prefix, after the 1h corpus: a follow-up
    /// question reads it from cache instead of paying for it again.
    func testDramaturgePlayIsTheLastCachedSystemBlock() throws {
        let r = try Atelier.dramaturgeRequest(lang: .fr, question: "Que veut Alice ?", play: "ALICE\nNon.", title: "La Marée",
                                              cast: ["ALICE", "BRUNO"], history: [])
        let blocks = try XCTUnwrap(r.systemBlocks)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].cacheControl, ClaudeCacheControl(ttl: .oneHour))  // core
        XCTAssertEqual(blocks[1].cacheControl, ClaudeCacheControl(ttl: .oneHour))  // dramaturge extras
        XCTAssertNil(blocks[2].cacheControl)                                        // task prompt
        XCTAssertEqual(blocks[3].cacheControl, ClaudeCacheControl())                // the play, 5 min, after the 1h blocks
        XCTAssertEqual(blocks[3].text, "<piece langue=\"fr\">\nTitre : La Marée\nDistribution : ALICE, BRUNO\n\nALICE\nNon.\n</piece>")
        XCTAssertLessThanOrEqual(blocks.filter { $0.cacheControl != nil }.count, 4)
        XCTAssertEqual(r.messages, [.user("Que veut Alice ?")])
        XCTAssertEqual(r.toolChoice, .tool("reponse"))
    }

    func testDramaturgeFollowUpKeepsTheWholeCachedPrefix() throws {
        let play = "ALICE\nNon.\n\nBRUNO\nOuvre."
        let q1 = try Atelier.dramaturgeRequest(lang: .fr, question: "Q1", play: play, title: nil, cast: ["ALICE"], history: [])
        let q2 = try Atelier.dramaturgeRequest(lang: .fr, question: "Q2", play: play, title: nil, cast: ["ALICE"],
                                               history: [DramaturgeTurn(role: "user", text: "Q1"), DramaturgeTurn(role: "assistant", text: "R1")])
        XCTAssertEqual(q1.tools, q2.tools)
        XCTAssertEqual(q1.systemBlocks, q2.systemBlocks)   // tools + system identical → question 2 reads corpus + play
        XCTAssertEqual(q2.messages, [.user("Q1"), .assistant("R1"), .user("Q2")])
    }

    func testDramaturgeResDecodes() throws {
        let r = try JSONDecoder().decode(DramaturgeRes.self, from: Data(#"{"answer":"Alice veut qu'il parte.","followups":["Et Bruno ?"]}"#.utf8))
        XCTAssertEqual(r.followups, ["Et Bruno ?"])
    }
}
