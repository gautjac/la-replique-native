import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

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
        // With element ids, so a restore keeps readers' notes attached.
        guard let data = try? PlayFormat.aiJSON(from: play, withElementIDs: true), let json = String(data: data, encoding: .utf8) else { return }
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
        #if DEBUG
        RenderCounter.log.debug("export aiJSON")
        #endif
        return (try? PlayFormat.aiJSON(from: play)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// A `ShareLink` payload that renders ONLY when the share actually happens.
///
/// The detail toolbar used to hold `ShareLink(item: Exports.aiJSONString(play))`,
/// which serialised the whole play every time the toolbar was built — and,
/// worse, reading every element's text there subscribed the detail view to
/// every line, so each keystroke re-rendered the detail view, the editor and
/// the page (measured on a 1500-element play: 3 keystrokes → 3 full exports +
/// 3 page rebuilds). Now only the play's identifier crosses into the toolbar.
struct PlayExport: Transferable, Sendable {
    enum Kind: Sendable { case text, aiJSON }
    let playID: PersistentIdentifier
    let kind: Kind
    let filename: String

    @MainActor
    init(_ play: Play, kind: Kind) {
        self.playID = play.persistentModelID
        self.kind = kind
        let base = play.title.isEmpty ? "piece" : play.title
        self.filename = kind == .text ? "\(base).txt" : "\(base).lareplique.json"
    }

    @MainActor
    func render() -> String {
        guard let play = Persistence.shared.mainContext.model(for: playID) as? Play else { return "" }
        return kind == .text ? Exports.plainText(play) : Exports.aiJSONString(play)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in Data(await item.render().utf8) }
            .exportingCondition { $0.kind == .aiJSON }
            .suggestedFileName { $0.filename }
        DataRepresentation(exportedContentType: .plainText) { item in Data(await item.render().utf8) }
            .exportingCondition { $0.kind == .text }
            .suggestedFileName { $0.filename }
    }
}
