import XCTest
import ClaudeKit
@testable import LaReplique

/// The craft corpus must ship inside the bundle and assemble into the same
/// block layout as the web function: shared cached core, per-op cached extras,
/// uncached task prompt.
final class CorpusTests: XCTestCase {

    private let ops = ["relance", "dramaturgie", "traduire", "retoucher", "voix", "etsi"]

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
        XCTAssertThrowsError(try Corpus.files(for: "nope")) { XCTAssertEqual($0 as? Corpus.CorpusError, .unknownOp("nope")) }
        for op in ops {
            let chars = try Corpus.system(op: op, task: "").reduce(0) { $0 + $1.text.count }
            XCTAssertLessThan(chars, 90_000, op) // ≈ 1 token per char in this corpus
        }
    }
}

/// The tool list is part of the cache prefix: fixed content, fixed order.
final class AtelierToolsTests: XCTestCase {
    func testOneFixedToolListInStableOrder() {
        XCTAssertEqual(Atelier.tools.map(\.name), ["proposer_replique", "notes", "voix", "et_si", "retoucher", "traduction"])
        for t in Atelier.tools { XCTAssertEqual(t.description, "Return the result.") }
    }
}
