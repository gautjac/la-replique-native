import Foundation
import SwiftData

/// A named snapshot of a play (stored as `la-replique/1` JSON). CloudKit-safe.
@Model
final class Version {
    var id: UUID = UUID()
    var playID: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var json: String = ""

    init(playID: UUID, name: String, json: String) {
        self.id = UUID()
        self.playID = playID
        self.name = name
        self.json = json
        self.createdAt = Date()
    }
}

@MainActor
enum Versions {
    static func save(_ play: Play, name: String, context: ModelContext) {
        guard let data = try? PlayFormat.aiJSON(from: play), let json = String(data: data, encoding: .utf8) else { return }
        context.insert(Version(playID: play.id, name: name.isEmpty ? "Version" : name, json: json))
    }

    /// Restore a snapshot into its play, in place (same Play id).
    static func restore(_ version: Version, into play: Play, context: ModelContext) {
        guard let doc = try? PlayFormat.decode(Data(version.json.utf8)) else { return }
        PlayFormat.replaceContent(of: play, with: doc, context: context)
    }
}

/// Text exports (share / print).
@MainActor
enum Exports {
    static func plainText(_ play: Play) -> String {
        var head = play.title.uppercased()
        if !play.subtitle.isEmpty { head += "\n" + play.subtitle }
        if !play.author.isEmpty { head += "\n" + (play.lang == .fr ? "de " : "by ") + play.author }
        return head + "\n\n\n" + Atelier.scriptText(play.elementList, play: play)
    }

    static func aiJSONString(_ play: Play) -> String {
        (try? PlayFormat.aiJSON(from: play)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
