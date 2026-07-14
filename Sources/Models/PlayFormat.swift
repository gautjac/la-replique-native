import Foundation
import SwiftData

// The portable `la-replique/1` document — the interchange format shared with the
// web app. Cues may reference a speaker by NAME (`character`/`speaker`) or by id.

struct PlayDoc: Codable {
    var format: String?
    var title: String?
    var subtitle: String?
    var author: String?
    var logline: String?
    var lang: String?
    var altLang: String?
    var characters: [CharDoc]?
    var elements: [ElDoc]
}

struct CharDoc: Codable {
    var id: String?
    var name: String?
    var color: String?
    var note: String?
    var voiceId: String?
}

struct ElDoc: Codable {
    var id: String?
    var type: String
    var label: String?
    var setting: String?
    var synopsis: String?
    var beat: String?
    var text: String?
    var parenthetical: String?
    var alt: String?
    var character: String?   // AI-friendly: speaker by name
    var speaker: String?     // alias
    var characterId: String? // backups: speaker by id
}

enum PlayFormat {
    // MARK: Decode

    static func decode(_ data: Data) throws -> PlayDoc {
        try JSONDecoder().decode(PlayDoc.self, from: data)
    }

    /// Build a SwiftData `Play` (with characters + elements) from a document and
    /// insert it into `context`. Cues resolve their speaker by name, auto-creating
    /// characters as needed — nothing is dropped.
    @MainActor
    @discardableResult
    static func makePlay(from doc: PlayDoc, into context: ModelContext) -> Play {
        let play = Play(title: "", lang: .fr)
        context.insert(play)
        populate(play, from: doc, context: context)
        return play
    }

    /// Replace a play's content from a document, keeping the same Play id (used by
    /// version restore).
    @MainActor
    static func replaceContent(of play: Play, with doc: PlayDoc, context: ModelContext) {
        for e in play.elementList { e.play = nil; context.delete(e) }
        for c in play.characterList { c.play = nil; context.delete(c) }
        populate(play, from: doc, context: context)
    }

    @MainActor
    private static func populate(_ play: Play, from doc: PlayDoc, context: ModelContext) {
        let lang = Lang(rawValue: doc.lang ?? "fr") ?? .fr
        play.lang = lang
        play.title = doc.title ?? (lang == .fr ? "Pièce importée" : "Imported play")
        play.subtitle = doc.subtitle ?? ""
        play.author = doc.author ?? ""
        if let logline = doc.logline { play.logline = logline }
        play.altLang = doc.altLang.flatMap(Lang.init(rawValue:))
        play.touch()

        var characters: [Character] = []
        var byName: [String: Character] = [:]
        func addChar(_ c: Character) {
            c.order = characters.count
            c.play = play
            characters.append(c)
            byName[c.name.lowercased()] = c
            context.insert(c)
        }

        for cd in doc.characters ?? [] {
            let name = (cd.name ?? "?")
            let color = cd.color ?? Theme.nextCastColor(used: characters.map(\.colorHex))
            let c = Character(name: name, colorHex: color)
            c.note = cd.note
            c.voiceID = cd.voiceId
            addChar(c)
        }

        func resolveSpeaker(_ el: ElDoc) -> String? {
            if let cid = el.characterId, let existing = characters.first(where: { $0.id.uuidString == cid }) {
                return existing.id.uuidString
            }
            let nameRef = (el.character ?? el.speaker)?.trimmingCharacters(in: .whitespaces)
            if let nameRef, !nameRef.isEmpty {
                if let existing = byName[nameRef.lowercased()] { return existing.id.uuidString }
                let created = Character(name: nameRef.uppercased(),
                                        colorHex: Theme.nextCastColor(used: characters.map(\.colorHex)))
                addChar(created)
                return created.id.uuidString
            }
            return nil
        }

        for (i, ed) in doc.elements.enumerated() {
            guard let kind = ElementKind(rawValue: ed.type) else { continue }
            let el = Element(kind: kind, order: i)
            switch kind {
            case .act:
                el.label = ed.label ?? ""
            case .scene:
                el.label = ed.label ?? ""
                el.setting = ed.setting
                el.synopsis = ed.synopsis
                if let b = ed.beat { el.beat = Beat(rawValue: b) }
            case .stage:
                el.text = ed.text ?? ""
                el.alt = ed.alt
            case .action:
                el.text = ed.text ?? ""
            case .cue:
                el.characterID = resolveSpeaker(ed)
                el.text = ed.text ?? ""
                el.parenthetical = ed.parenthetical
                el.alt = ed.alt
            }
            el.play = play
            context.insert(el)
        }
    }

    // MARK: Encode (clean AI-friendly export — speakers by name)

    @MainActor
    static func aiDoc(from play: Play) -> PlayDoc {
        let chars = play.characterList.map {
            CharDoc(id: nil, name: $0.name, color: nil,
                    note: ($0.note?.isEmpty == false) ? $0.note : nil,
                    voiceId: $0.voiceID)
        }
        let els: [ElDoc] = play.elementList.map { el in
            switch el.kind {
            case .act:
                return ElDoc(type: "act", label: el.label)
            case .scene:
                return ElDoc(type: "scene", label: el.label,
                             setting: nn(el.setting), synopsis: nn(el.synopsis), beat: el.beat?.rawValue)
            case .stage:
                return ElDoc(type: "stage", text: el.text, alt: nn(el.alt))
            case .action:
                return ElDoc(type: "action", text: el.text)
            case .cue:
                return ElDoc(type: "cue", text: el.text, parenthetical: nn(el.parenthetical),
                             alt: nn(el.alt), character: play.character(id: el.characterID)?.name ?? "?")
            }
        }
        return PlayDoc(format: "la-replique/1", title: play.title,
                       subtitle: nn(play.subtitle), author: nn(play.author),
                       logline: nn(play.logline),
                       lang: play.lang.rawValue, altLang: play.altLang?.rawValue,
                       characters: chars, elements: els)
    }

    @MainActor
    static func aiJSON(from play: Play) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try enc.encode(aiDoc(from: play))
    }

    private static func nn(_ s: String?) -> String? { (s?.isEmpty == false) ? s : nil }
}
