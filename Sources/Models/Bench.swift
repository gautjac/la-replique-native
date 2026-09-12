import Foundation
import OSLog
import SwiftData

#if DEBUG
/// DEBUG-only render accounting for the editor. Every editor page/row body
/// evaluation (and every binding write, `set <id>`) logs one line under
/// subsystem `app.atelier.lareplique`, category `render`, so a keystroke's cost
/// can be counted from outside (method + numbers: docs/EDITOR_PERFORMANCE.md):
///
///   xcrun simctl spawn booted log stream --level debug \
///     --predicate 'subsystem == "app.atelier.lareplique" AND category == "render"'
///
/// This is how the 2026-09-12 editor refactor was measured (one keystroke used
/// to rebuild every row of the play; it now rebuilds one).
enum RenderCounter {
    static let log = Logger(subsystem: "app.atelier.lareplique", category: "render")
    static func page(_ count: Int) { log.debug("page body · \(count, privacy: .public) elements") }
    static func row(_ id: UUID) { log.debug("row body · \(id.uuidString.prefix(8), privacy: .public)") }
}

/// DEBUG-only synthetic play for measuring editor cost at size.
/// Launch with the env var `LR_BENCH=<n>` (simctl: `SIMCTL_CHILD_LR_BENCH=1500`)
/// to get a play titled "Banc d'essai" with `n` elements (two speakers, a scene
/// heading every 40 lines, a didascalie every 15). Idempotent: an existing
/// "Banc d'essai" is left alone.
@MainActor
enum Bench {
    static let title = "Banc d'essai"

    static func seedIfRequested(_ context: ModelContext) -> Play? {
        guard let raw = ProcessInfo.processInfo.environment["LR_BENCH"], let n = Int(raw), n > 0 else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<Play>())) ?? []
        if let p = existing.first(where: { $0.title == title }) { return p }
        let play = Play(title: title, lang: .fr)
        context.insert(play)
        let a = Character(name: "ANNE", colorHex: "#4f7cff", order: 0)
        let b = Character(name: "BRUNO", colorHex: "#0ea5b7", order: 1)
        a.play = play; b.play = play
        context.insert(a); context.insert(b)
        for i in 0..<n {
            let el: Element
            if i % 40 == 0 {
                el = Element(kind: .scene, order: i)
                el.label = Labels.scene(i / 40 + 1, .fr)
                el.setting = "Le quai. Nuit."
            } else if i % 15 == 0 {
                el = Element(kind: .stage, order: i)
                el.text = "Un temps. La lampe vacille."
            } else {
                el = Element(kind: .cue, order: i)
                el.characterID = (i % 2 == 0 ? a : b).id.uuidString
                el.text = "Réplique numéro \(i) — ce que je te dis là, je te l'ai déjà dit cent fois."
            }
            el.play = play
            context.insert(el)
        }
        try? context.save()
        return play
    }
}
#endif
