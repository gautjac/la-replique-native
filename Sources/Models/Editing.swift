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

    /// Remove a character; their lines are kept (unassigned), never deleted.
    static func removeCharacter(_ play: Play, _ char: Character, context: ModelContext) {
        let cid = char.id.uuidString
        for el in play.elementList where el.kind == .cue && el.characterID == cid { el.characterID = nil }
        char.play = nil
        context.delete(char)
        play.touch()
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

    // MARK: Beat-board blocks (act heading, or scene heading + its body)

    struct Block: Identifiable {
        let id: UUID
        let isAct: Bool
        var els: [Element]
        var heading: Element { els[0] }
    }

    static func decompose(_ play: Play) -> (preamble: [Element], blocks: [Block]) {
        var preamble: [Element] = []
        var blocks: [Block] = []
        var cur: Block?
        for el in sorted(play) {
            if el.kind == .act {
                if let c = cur { blocks.append(c); cur = nil }
                blocks.append(Block(id: el.id, isAct: true, els: [el]))
            } else if el.kind == .scene {
                if let c = cur { blocks.append(c) }
                cur = Block(id: el.id, isAct: false, els: [el])
            } else if cur != nil {
                cur!.els.append(el)
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].els.append(el)
            } else {
                preamble.append(el)
            }
        }
        if let c = cur { blocks.append(c) }
        return (preamble, blocks)
    }

    private static func recompose(_ preamble: [Element], _ blocks: [Block]) {
        renumber(preamble + blocks.flatMap(\.els))
    }

    static func moveBlock(_ play: Play, blockID: UUID, dir: Int) {
        var (pre, blocks) = decompose(play)
        guard let i = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let j = i + dir
        guard j >= 0, j < blocks.count else { return }
        blocks.swapAt(i, j)
        recompose(pre, blocks)
        play.touch()
    }

    /// Move a block so it sits immediately before `targetID` (or to the very end
    /// when `targetID` is nil). Powers the board's drag-and-drop and act picker.
    static func moveBlock(_ play: Play, blockID: UUID, before targetID: UUID?) {
        guard blockID != targetID else { return }
        var (pre, blocks) = decompose(play)
        guard let from = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let moving = blocks.remove(at: from)
        let to = targetID.flatMap { id in blocks.firstIndex { $0.id == id } } ?? blocks.count
        blocks.insert(moving, at: min(to, blocks.count))
        recompose(pre, blocks)
        play.touch()
    }

    /// Remove a scene heading, keeping its dialogue (the lines fold into the
    /// preceding block). Non-destructive — the words survive.
    static func removeSceneHeading(_ play: Play, sceneID: UUID, context: ModelContext) {
        guard let heading = (play.elements ?? []).first(where: { $0.id == sceneID && $0.kind == .scene }) else { return }
        heading.play = nil
        context.delete(heading)
        let (pre, blocks) = decompose(play)
        recompose(pre, blocks)
        play.touch()
    }

    @discardableResult
    static func addSceneAfter(_ play: Play, blockID: UUID?, context: ModelContext) -> Element {
        var (pre, blocks) = decompose(play)
        let n = blocks.filter { !$0.isAct }.count + 1
        let heading = Element(kind: .scene)
        heading.label = Labels.scene(n, play.lang); heading.setting = ""
        heading.play = play
        context.insert(heading)
        let block = Block(id: heading.id, isAct: false, els: [heading])
        let at = blockID.flatMap { id in blocks.firstIndex { $0.id == id } } ?? (blocks.count - 1)
        blocks.insert(block, at: min(at + 1, blocks.count))
        recompose(pre, blocks)
        play.touch()
        return heading
    }

    @discardableResult
    static func addActAtEnd(_ play: Play, context: ModelContext) -> Element {
        let n = sorted(play).filter { $0.kind == .act }.count + 1
        let act = Element(kind: .act, order: sorted(play).count)
        act.label = Labels.act(n, play.lang)
        act.play = play
        context.insert(act)
        play.touch()
        return act
    }

    /// Type-ahead speaker on a cue: space switches to an existing cast member by
    /// name; colon switches or creates. Returns whether it handled the token.
    @discardableResult
    /// The best cast member whose name begins with `prefix` (case-insensitive),
    /// for the cue speaker autocomplete. nil if the prefix is empty or unmatched.
    static func suggestSpeaker(_ play: Play, prefix: String) -> Character? {
        let p = prefix.trimmingCharacters(in: .whitespaces).uppercased()
        guard !p.isEmpty else { return nil }
        return play.characterList.first { $0.name.uppercased().hasPrefix(p) }
    }

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
