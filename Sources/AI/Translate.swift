import Foundation
import SwiftData

/// Build a translation bundle from a play and turn a translated bundle back into
/// a NEW play. Structure stays local; only free text crosses to the model.
@MainActor
enum Translate {
    static func buildBundle(_ play: Play) -> [BundleItem] {
        var items: [BundleItem] = []
        func push(_ k: String, _ t: String?) { if let t, !t.isEmpty { items.append(BundleItem(k: k, t: t)) } }
        push("title", play.title)
        push("subtitle", play.subtitle)
        for c in play.characterList { push("cnote:\(c.id.uuidString)", c.note) }
        for el in play.elementList {
            let id = el.id.uuidString
            switch el.kind {
            case .scene: push("setting:\(id)", el.setting)
            case .stage: push("stage:\(id)", el.text)
            case .action: push("action:\(id)", el.text)
            case .cue: push("cue:\(id)", el.text); push("paren:\(id)", el.parenthetical)
            case .act: break
            }
        }
        return items
    }

    @discardableResult
    static func makeTranslatedPlay(_ play: Play, to: Lang, items: [BundleItem], context: ModelContext) -> Play {
        var map: [String: String] = [:]
        for i in items { map[i.k] = i.t }
        func get(_ k: String, _ fallback: String?) -> String? { map[k] ?? fallback }

        let suffix = to == .fr ? " (FR)" : " (EN)"
        let np = Play(title: (get("title", play.title) ?? play.title) + suffix, lang: to)
        np.subtitle = get("subtitle", play.subtitle) ?? ""
        np.author = play.author
        context.insert(np)

        var charMap: [String: Character] = [:]
        for (i, c) in play.characterList.enumerated() {
            let nc = Character(name: c.name, colorHex: c.colorHex, order: i)
            nc.note = get("cnote:\(c.id.uuidString)", c.note)
            nc.voiceID = c.voiceID
            nc.play = np
            context.insert(nc)
            charMap[c.id.uuidString] = nc
        }

        var actN = 0, sceneN = 0
        for (idx, el) in play.elementList.enumerated() {
            let id = el.id.uuidString
            let ne = Element(kind: el.kind, order: idx)
            switch el.kind {
            case .act: actN += 1; ne.label = Labels.act(actN, to)
            case .scene:
                sceneN += 1; ne.label = Labels.scene(sceneN, to)
                ne.setting = get("setting:\(id)", el.setting)
                ne.synopsis = el.synopsis; ne.beat = el.beat
            case .stage: ne.text = get("stage:\(id)", el.text)
            case .action: ne.text = get("action:\(id)", el.text)
            case .cue:
                ne.characterID = el.characterID.flatMap { charMap[$0]?.id.uuidString }
                ne.text = get("cue:\(id)", el.text)
                ne.parenthetical = get("paren:\(id)", el.parenthetical)
            }
            ne.play = np
            context.insert(ne)
        }
        return np
    }
}
