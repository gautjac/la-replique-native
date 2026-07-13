import SwiftUI

/// First-run welcome. Explains what La Réplique is in a few beats, then hands off
/// to writing (and, optionally, to adding a Claude key for the Atelier).
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called when the reader taps "Ajouter ma clé Claude".
    var onAddKey: () -> Void

    private struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        .init(icon: "keyboard",
              title: "Écris au clavier",
              body: "Entrée pour une réplique, Tab pour changer de personnage. La mise en page suit."),
        .init(icon: "sparkles",
              title: "L'Atelier, à ta main",
              body: "Relances, dramaturgie, traduction — avec ta propre clé Claude, sur ton appareil."),
        .init(icon: "speaker.wave.2",
              title: "Lecture à voix",
              body: "Entends la pièce : chaque personnage prend une voix distincte."),
        .init(icon: "globe",
              title: "Partage la lecture",
              body: "Publie une pièce en lecture seule et envoie un simple lien web."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.gel)
                        Text("La Réplique")
                            .font(.largeTitle.weight(.bold))
                        Text("Un atelier d'écriture pour la scène — bilingue, sur iPhone, iPad et Mac.")
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
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
            }

            VStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text("Commencer à écrire").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    dismiss()
                    onAddKey()
                } label: {
                    Text("Ajouter ma clé Claude").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Tes clés restent sur cet appareil. Rien n'est obligatoire pour commencer.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial)
        }
        .background(Theme.desk)
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .interactiveDismissDisabled()
    }
}
