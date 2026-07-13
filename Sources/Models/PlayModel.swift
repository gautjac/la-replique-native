import Foundation
import SwiftData

// MARK: - Enums (stored as raw strings for forward-compatibility + CloudKit)

enum Lang: String, Codable, CaseIterable, Sendable {
    case fr, en
    var label: String { self == .fr ? "Français" : "English" }
}

/// The five element kinds — mirrors the web model exactly.
enum ElementKind: String, Codable, CaseIterable, Sendable {
    case act, scene, stage, cue, action
}

/// Dramaturgical beat a scene can carry (beat board), in narrative order.
enum Beat: String, Codable, CaseIterable, Sendable {
    case setup, inciting, rising, turn, crisis, climax, resolution
}

// MARK: - Models
//
// CloudKit rules honoured throughout: every stored property has a default or is
// optional, there are NO unique constraints, and to-many relationships are
// optional. Non-optional `…List` accessors keep call sites clean.

@Model
final class Play {
    var id: UUID = UUID()
    var title: String = ""
    var subtitle: String = ""
    var author: String = ""
    var langRaw: String = Lang.fr.rawValue
    var altLangRaw: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Character.play)
    var characters: [Character]?
    @Relationship(deleteRule: .cascade, inverse: \Element.play)
    var elements: [Element]?

    init(title: String = "", lang: Lang = .fr) {
        self.id = UUID()
        self.title = title
        self.langRaw = lang.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var lang: Lang {
        get { Lang(rawValue: langRaw) ?? .fr }
        set { langRaw = newValue.rawValue }
    }
    var altLang: Lang? {
        get { altLangRaw.flatMap(Lang.init(rawValue:)) }
        set { altLangRaw = newValue?.rawValue }
    }

    var characterList: [Character] { (characters ?? []).sorted { $0.order < $1.order } }
    var elementList: [Element] { (elements ?? []).sorted { $0.order < $1.order } }

    func character(id: String?) -> Character? {
        guard let id else { return nil }
        return (characters ?? []).first { $0.id.uuidString == id }
    }

    func touch() { updatedAt = Date() }
}

@Model
final class Character {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var colorHex: String = "#4f7cff"
    var note: String?
    var voiceID: String?
    var play: Play?

    init(name: String = "", colorHex: String = "#4f7cff", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }
}

@Model
final class Element {
    var id: UUID = UUID()
    var order: Int = 0
    var kindRaw: String = ElementKind.cue.rawValue

    /// For cues: the speaking Character's `id.uuidString`.
    var characterID: String?
    var text: String?
    var label: String?
    var setting: String?
    var synopsis: String?
    var beatRaw: String?
    var parenthetical: String?
    /// Other-language line for surtitles.
    var alt: String?
    var play: Play?

    init(kind: ElementKind = .cue, order: Int = 0) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.order = order
    }

    var kind: ElementKind {
        get { ElementKind(rawValue: kindRaw) ?? .cue }
        set { kindRaw = newValue.rawValue }
    }
    var beat: Beat? {
        get { beatRaw.flatMap(Beat.init(rawValue:)) }
        set { beatRaw = newValue?.rawValue }
    }
}
