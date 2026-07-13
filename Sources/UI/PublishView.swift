import SwiftUI
import SwiftData

/// "Partager la lecture" — publishes the play read-only to the web viewer and
/// surfaces the link (copy / open / share). Dépublier removes it.
struct PublishView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Bindable var play: Play

    @State private var busy = false
    @State private var error: String?
    @State private var justCopied = false

    private var shareURL: URL? { play.publicShareID.map(Publish.webURL) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = shareURL {
                        published(url)
                    } else {
                        unpublished
                    }
                } footer: {
                    Text("Une lecture publiée est en lecture seule sur le web — le texte, pas le fichier modifiable. N'importe qui avec le lien peut la lire.")
                }

                if let error {
                    Section { Text(error).font(.callout).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Partager la lecture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 380)
        #endif
    }

    // MARK: - Not yet published

    @ViewBuilder private var unpublished: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pas encore partagée", systemImage: "lock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Publie « \(play.title.isEmpty ? "cette pièce" : play.title) » pour obtenir un lien de lecture web.")
                .font(.callout)
            Button {
                run { try await Publish.publish(play, context: context) }
            } label: {
                Label("Publier — lecture seule", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Published

    @ViewBuilder private func published(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Publiée", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.jade)

            Text(url.absoluteString)
                .font(.callout.monospaced())
                .foregroundStyle(Theme.gel)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Button { copy(url.absoluteString) } label: {
                    Label(justCopied ? "Copié" : "Copier le lien",
                          systemImage: justCopied ? "checkmark" : "doc.on.doc")
                }
                Button { openURL(url) } label: {
                    Label("Ouvrir", systemImage: "safari")
                }
                ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
            }
            .buttonStyle(.bordered)

            Divider().padding(.vertical, 2)

            HStack {
                Button {
                    run { _ = try await Publish.publish(play, context: context) }
                } label: {
                    Label("Mettre à jour", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
                Spacer()
                Button(role: .destructive) {
                    run { try await Publish.unpublish(play, context: context) }
                } label: {
                    Label("Dépublier", systemImage: "trash")
                }
                .disabled(busy)
            }
            .font(.callout)

            Text("« Mettre à jour » republie la version actuelle sous le même lien.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .center) { if busy { ProgressView() } }
    }

    // MARK: - Actions

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task { @MainActor in
            do { try await op() }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
        justCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            justCopied = false
        }
    }
}
