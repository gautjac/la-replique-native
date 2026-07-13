import AppIntents
import SwiftData
import Foundation

// MARK: - Play entity (so Shortcuts can pick a play)

struct PlayEntity: AppEntity, Identifiable {
    let id: UUID
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Pièce" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    static var defaultQuery: PlayQuery { PlayQuery() }

    init(id: UUID, title: String) { self.id = id; self.title = title }
    init(_ play: Play) {
        self.init(id: play.id, title: play.title.isEmpty ? "Pièce sans titre" : play.title)
    }
}

struct PlayQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlayEntity] {
        try allPlays().filter { identifiers.contains($0.id) }.map(PlayEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PlayEntity] {
        Array(try allPlays().prefix(12)).map(PlayEntity.init)
    }

    @MainActor
    private func allPlays() throws -> [Play] {
        let ctx = ModelContext(Persistence.shared)
        return try ctx.fetch(FetchDescriptor<Play>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }
}

// MARK: - New play

struct NewPlayIntent: AppIntent {
    static var title: LocalizedStringResource { "Nouvelle pièce" }
    static var description: IntentDescription { IntentDescription("Crée une nouvelle pièce et l'ouvre dans La Réplique.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Titre", default: "")
    var titleText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Nouvelle pièce intitulée \(\.$titleText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let ctx = ModelContext(Persistence.shared)
        let clean = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let play = Play(title: clean.isEmpty ? "Pièce sans titre" : clean, lang: .fr)
        ctx.insert(play)
        try? ctx.save()
        AppRouter.shared.openPlayID = play.id
        return .result()
    }
}

// MARK: - Publish read-only to the web

struct PublishPlayIntent: AppIntent {
    static var title: LocalizedStringResource { "Publier une lecture" }
    static var description: IntentDescription {
        IntentDescription("Publie une pièce en lecture seule sur le web et renvoie le lien à partager.")
    }

    @Parameter(title: "Pièce")
    var play: PlayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Publier \(\.$play) en lecture seule")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let ctx = ModelContext(Persistence.shared)
        let pid = play.id
        guard let model = try ctx.fetch(
            FetchDescriptor<Play>(predicate: #Predicate { $0.id == pid })
        ).first else {
            throw AppIntentError.notFound
        }
        let shareID = try await Publish.publish(model, context: ctx)
        let link = Publish.webURL(for: shareID).absoluteString
        return .result(value: link, dialog: IntentDialog("Publiée. Lien : \(link)"))
    }
}

// MARK: - Errors

enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: return "Pièce introuvable."
        }
    }
}

// MARK: - Shortcuts surfaced to Siri / Spotlight

struct RepliqueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewPlayIntent(),
            phrases: [
                "Nouvelle pièce dans \(.applicationName)",
                "Créer une pièce dans \(.applicationName)",
                "New play in \(.applicationName)"
            ],
            shortTitle: "Nouvelle pièce",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: PublishPlayIntent(),
            phrases: [
                "Publier une lecture dans \(.applicationName)",
                "Partager une pièce avec \(.applicationName)",
                "Publish a play in \(.applicationName)"
            ],
            shortTitle: "Publier une lecture",
            systemImageName: "globe"
        )
    }
}
