import SwiftUI

/// « Écrire à plusieurs » — shown once, the first time a shared play opens on
/// this device, and any time after from the ••• menu. The first-run welcome
/// (`OnboardingView`) is about writing alone; this one is about writing with
/// others: roles, notes, history, versions, offline, the browser.
struct CollabOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared

    private struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let points: [Point] = [
        .init(icon: "person.2",
              title: "Trois rôles",
              body: "Écrire change le texte. Commenter laisse des notes sans toucher au texte. Lire regarde. La personne qui a partagé la pièce choisit le rôle de chaque invitation, et peut le changer après."),
        .init(icon: "text.bubble",
              title: "Une note, sur une ligne",
              body: "Passe sur une réplique et touche la bulle à sa droite. Le survol montre l'aperçu des notes ; un double-clic ouvre le fil pour répondre ou régler."),
        .init(icon: "clock",
              title: "L'historique",
              body: "Chaque changement est signé : qui, quand, quels mots. Le bouton de l'horloge en haut les liste ; « Restaurer ce texte » ramène la version d'avant en un geste."),
        .init(icon: "camera",
              title: "Les versions",
              body: "Avant une lecture, enregistre une version nommée depuis le menu •••. Compare-la à maintenant ou à une autre, et restaure-la au besoin."),
        .init(icon: "wifi.slash",
              title: "Hors ligne, sans souci",
              body: "Chacun garde sa copie ; tout se réconcilie au retour du réseau. Une ligne que quelqu'un d'autre est en train d'écrire se verrouille un instant, avec son nom dessus."),
        .init(icon: "globe",
              title: "Aussi dans un navigateur",
              body: "Sans appareil Apple, on écrit avec le même code sur la-replique.netlify.app/ecrire — mêmes notes, même historique, mêmes versions."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "person.2.wave.2")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.gel)
                        Text("Écrire à plusieurs")
                            .font(.largeTitle.weight(.bold))
                        Text("Cette pièce est partagée : ce que tu écris apparaît chez les autres en direct, signé de ton nom.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(points) { p in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: p.icon)
                                    .font(.title3)
                                    .foregroundStyle(Theme.gelBright)
                                    .frame(width: 30, alignment: .center)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.title).font(.headline)
                                    Text(p.body).font(.subheadline).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
            }

            VStack(spacing: 10) {
                Button { dismiss() } label: { Text("Compris").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Tu retrouves cette page dans le menu ••• : « À plusieurs : comment ça marche ».")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial)
        }
        .background(Theme.desk)
        .id(loc.language)
        #if os(macOS)
        .frame(width: 560, height: 660)
        #endif
    }
}
