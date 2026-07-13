import Foundation
import SwiftData

/// Auto-labels for act/scene headings, language-aware.
enum Labels {
    static func roman(_ n: Int) -> String {
        guard n >= 1, n <= 39 else { return String(n) }
        let map: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var out = ""; var x = n
        for (v, s) in map { while x >= v { out += s; x -= v } }
        return out
    }
    static func act(_ n: Int, _ lang: Lang) -> String { "\(lang == .fr ? "ACTE" : "ACT") \(roman(n))" }
    static func scene(_ n: Int, _ lang: Lang) -> String { "\(lang == .fr ? "SCÈNE" : "SCENE") \(n)" }
}

/// Structural edits on a Play's elements. All @MainActor (they touch SwiftData).
/// `order` is renumbered to array position after each structural change, so it
/// always reads 0…n-1 in document order.
@MainActor
enum Editing {
    static func sorted(_ play: Play) -> [Element] { play.elementList }

    private static func renumber(_ arr: [Element]) {
        for (i, e) in arr.enumerated() { e.order = i }
    }

    static func cycleKind(_ k: ElementKind) -> ElementKind {
        let order: [ElementKind] = [.cue, .stage, .scene, .act, .action]
        let i = order.firstIndex(of: k) ?? 0
        return order[(i + 1) % order.count]
    }

    /// The distinct speakers (character ids) in the scene containing `el`.
    static func sceneSpeakers(_ play: Play, around el: Element) -> [String] {
        let arr = sorted(play)
        guard let idx = arr.firstIndex(where: { $0.id == el.id }) else { return [] }
        var start = 0
        for i in stride(from: idx, through: 0, by: -1) where arr[i].kind == .scene { start = i; break }
        var end = arr.count
        for i in (start + 1)..<arr.count where arr[i].kind == .scene { end = i; break }
        var seen: [String] = []
        for e in arr[start..<end] where e.kind == .cue {
            if let cid = e.characterID, !seen.contains(cid) { seen.append(cid) }
        }
        return seen
    }

    /// In a two-speaker scene, the speaker to switch to for the next réplique.
    static func alternateSpeaker(_ play: Play, after el: Element) -> String? {
        guard el.kind == .cue, let cid = el.characterID else { return nil }
        let speakers = sceneSpeakers(play, around: el)
        guard speakers.count == 2 else { return nil }
        return speakers.first { $0 != cid }
    }

    static func lastSpeakerBefore(_ play: Play, _ el: Element?) -> String? {
        let arr = sorted(play)
        let upto = el.flatMap { e in arr.firstIndex { $0.id == e.id } } ?? arr.count
        for e in arr[0..<min(upto + (el == nil ? 0 : 1), arr.count)].reversed() where e.kind == .cue {
            if let cid = e.characterID { return cid }
        }
        return play.characterList.first?.id.uuidString
    }

    // MARK: Characters

    static func findCharacter(_ play: Play, name: String) -> Character? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return play.characterList.first { $0.name.lowercased() == n }
    }

    @discardableResult
    static func addCharacter(_ play: Play, name: String, context: ModelContext) -> Character {
        let used = play.characterList.map(\.colorHex)
        let c = Character(name: name.trimmingCharacters(in: .whitespaces),
                          colorHex: Theme.nextCastColor(used: used),
                          order: play.characterList.count)
        c.play = play
        context.insert(c)
        play.touch()
        return c
    }

    // MARK: Elements

    /// Insert a fresh element of `kind` after `after` (or at end when nil).
    @discardableResult
    static func insert(_ kind: ElementKind, after: Element?, play: Play, context: ModelContext,
                       speaker: String? = nil) -> Element {
        var arr = sorted(play)
        let el = Element(kind: kind)
        switch kind {
        case .act: el.label = Labels.act(arr.filter { $0.kind == .act }.count + 1, play.lang)
        case .scene: el.label = Labels.scene(arr.filter { $0.kind == .scene }.count + 1, play.lang); el.setting = ""
        case .cue: el.characterID = speaker ?? lastSpeakerBefore(play, after)
        default: break
        }
        el.play = play
        context.insert(el)
        let idx = after.flatMap { a in arr.firstIndex { $0.id == a.id } } ?? (arr.count - 1)
        arr.insert(el, at: min(idx + 1, arr.count))
        renumber(arr)
        play.touch()
        return el
    }

    /// Convert an element's kind, carrying its text where it makes sense.
    static func convert(_ el: Element, to kind: ElementKind, play: Play, context: ModelContext) {
        guard el.kind != kind else { return }
        let src = el.text ?? el.label ?? ""
        // clear the fields we don't carry
        el.text = nil; el.label = nil; el.setting = nil; el.parenthetical = nil
        el.kind = kind
        switch kind {
        case .cue:
            el.text = src
            el.characterID = lastSpeakerBefore(play, el)
        case .stage, .action:
            el.text = src
        case .scene:
            let n = sorted(play).prefix { $0.id != el.id }.filter { $0.kind == .scene }.count + 1
            el.label = src.isEmpty ? Labels.scene(n, play.lang) : src
            el.setting = ""
        case .act:
            let n = sorted(play).prefix { $0.id != el.id }.filter { $0.kind == .act }.count + 1
            el.label = src.isEmpty ? Labels.act(n, play.lang) : src
        }
        play.touch()
    }

    /// Remove an element; returns the previous one (for focus).
    @discardableResult
    static func remove(_ el: Element, play: Play, context: ModelContext) -> Element? {
        var arr = sorted(play)
        guard let idx = arr.firstIndex(where: { $0.id == el.id }) else { return nil }
        let prev = idx > 0 ? arr[idx - 1] : nil
        arr.remove(at: idx)
        el.play = nil          // detach from the relationship synchronously (UI + order)
        context.delete(el)
        renumber(arr)
        play.touch()
        return prev
    }

    /// Type-ahead speaker on a cue: space switches to an existing cast member by
    /// name; colon switches or creates. Returns whether it handled the token.
    @discardableResult
    static func typeAhead(_ el: Element, token: String, allowCreate: Bool, play: Play, context: ModelContext) -> Bool {
        let name = token.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, el.kind == .cue else { return false }
        if let existing = findCharacter(play, name: name) {
            el.characterID = existing.id.uuidString
            el.text = ""
            play.touch()
            return true
        }
        if allowCreate {
            let c = addCharacter(play, name: name.uppercased(), context: context)
            el.characterID = c.id.uuidString
            el.text = ""
            return true
        }
        return false
    }
}
