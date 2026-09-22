import Foundation

// The shared shape of a collaborative play — what travels between people.
//
// A shared play is a small tree of flat documents:
//   plays/{playID}                 → the `info` entity (title, author, language…)
//   plays/{playID}/characters/{id} → one per character
//   plays/{playID}/elements/{id}   → one per block of the script, with `orderKey`
//
// Every value is a string (enums travel as raw values, ids as UUID strings), and
// an absent key means nil. Writes are FIELD-level, so two people changing
// different fields of the same line both win; the same field is last-writer-wins.

enum EntityKind: String, Codable, Sendable, CaseIterable { case info, character, element }

struct EntityRef: Hashable, Codable, Sendable, CustomStringConvertible {
    var kind: EntityKind
    var id: String
    static let info = EntityRef(kind: .info, id: "info")
    var description: String { "\(kind.rawValue):\(id)" }
}

typealias Fields = [String: String]

/// What this client asks the server to do.
enum CollabOp: Equatable, Sendable {
    /// Create (or wholly replace) an entity.
    case put(EntityRef, Fields)
    /// Change some fields of an EXISTING entity. Must fail — not resurrect — if the
    /// entity is gone: when one person deletes a line another is editing, delete wins.
    case patch(EntityRef, set: Fields, unset: [String])
    case delete(EntityRef)

    var ref: EntityRef {
        switch self { case .put(let r, _), .patch(let r, _, _), .delete(let r): return r }
    }
}

/// What the server tells this client.
///
/// CONTRACT (Firestore listener semantics, which every transport must honour):
/// changes arrive in server order, and what they describe is the server's state
/// OVERLAID WITH THIS CLIENT'S OWN UNACKNOWLEDGED WRITES. So a client never sees
/// its own line snap back to an older value while its newer write is in flight.
enum RemoteChange: Equatable, Sendable {
    case upsert(EntityRef, Fields)
    case removed(EntityRef)
}

enum CollabField {
    // info
    static let title = "title", subtitle = "subtitle", author = "author", logline = "logline"
    static let lang = "lang", altLang = "altLang"
    // character
    static let name = "name", color = "color", note = "note", voiceID = "voiceID", order = "order"
    // element
    static let kind = "kind", characterID = "characterID", text = "text", label = "label"
    static let setting = "setting", synopsis = "synopsis", beat = "beat"
    static let parenthetical = "parenthetical", alt = "alt", orderKey = "orderKey"
}

/// Who last changed a line, and when. Travels beside the script as `_by`,
/// `_byName`, `_at` on the element's document — META fields: the transports strip
/// every `_`-prefixed key before the core sees a document, so attribution can
/// never be mistaken for script content (or echo, or conflict).
struct LineEdit: Equatable, Sendable {
    var uid: String
    var name: String
    var at: Date
}
