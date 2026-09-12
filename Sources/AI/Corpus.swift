import Foundation
import ClaudeKit

/// Anchors `Bundle(for:)` to the app bundle, so the corpus resolves in unit
/// tests too (the test bundle is not the app bundle).
final class CorpusMarker {}

/// The Atelier's craft corpus — the screenwriting / dramaturgy skills
/// (jtydhr88/screenwriting-skills) vendored as app resources under `Corpus/`.
/// `Corpus/manifest.json` is the single source of truth for what each op sees;
/// it is mirrored from the web app by `npm run corpus:sync` over there. Same
/// block layout as the web function (`netlify/functions/lib/corpus.ts`):
///
///   [0] core   = PREAMBLE + terms table + dialogue + scene craft + character   (cached 1h, shared by ALL ops)
///   [1] extras = the op's own reference files, when it has any               (cached 1h, per op)
///   [2] task   = the op's instruction prompt                                  (not cached)
///
/// BYOK means the cache lives under the user's own key; the 1h TTL covers the
/// gaps of a writing session. The task prompt is small and varies; it stays
/// after the last breakpoint so it never breaks the prefix.
enum Corpus {
    struct Manifest: Decodable, Sendable {
        struct Source: Decodable, Sendable {
            let repo: String
            let commit: String
            let syncedAt: String
        }
        let source: Source
        let core: [String]
        let ops: [String: [String]]
    }

    enum CorpusError: Error, Equatable {
        case missing(String)
        case unknownOp(String)
    }

    /// Where the vendored files live inside the app bundle.
    static var directory: URL {
        Bundle(for: CorpusMarker.self).resourceURL!.appendingPathComponent("Corpus", isDirectory: true)
    }

    static let manifest: Manifest = {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else {
            fatalError("Corpus/manifest.json missing from the bundle — is `Corpus` a folder reference in project.yml?")
        }
        return m
    }()

    static var ops: [String] { manifest.ops.keys.sorted() }

    /// Read one vendored file (path relative to the corpus dir).
    static func file(_ rel: String) throws -> String {
        let url = directory.appendingPathComponent(rel)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CorpusError.missing(rel) }
        return text
    }

    static func preamble() throws -> String {
        try file("PREAMBLE.md").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One vendored file, wrapped so the model can tell files apart.
    static func wrap(_ rel: String) throws -> String {
        "<craft-reference file=\"\(rel)\">\n\(try file(rel).trimmingCharacters(in: .whitespacesAndNewlines))\n</craft-reference>"
    }

    /// The core block — identical for every op (the shared cache prefix).
    static func coreText() throws -> String {
        try ([preamble()] + manifest.core.map(wrap)).joined(separator: "\n\n")
    }

    /// The op's extras block, or nil when the op has none.
    static func extrasText(op: String) throws -> String? {
        guard let files = manifest.ops[op] else { throw CorpusError.unknownOp(op) }
        if files.isEmpty { return nil }
        return try files.map(wrap).joined(separator: "\n\n")
    }

    /// Which vendored files an op sees, core first.
    static func files(for op: String) throws -> [String] {
        guard let extras = manifest.ops[op] else { throw CorpusError.unknownOp(op) }
        return manifest.core + extras
    }

    /// The full `system` array for an op: cached craft blocks, then the task prompt.
    static func system(op: String, task: String, ttl: ClaudeCacheControl.TTL = .oneHour) throws -> [ClaudeSystemBlock] {
        var blocks: [ClaudeSystemBlock] = [.cached(try coreText(), ttl: ttl)]
        if let extras = try extrasText(op: op) { blocks.append(.cached(extras, ttl: ttl)) }
        blocks.append(ClaudeSystemBlock(text: task))
        return blocks
    }
}
