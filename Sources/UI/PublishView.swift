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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let url = shareURL { published(url) } else { unpublished }

                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Theme.rose)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Text("Une lecture publiée est en lecture seule sur le web — le texte, pas le fichier modifiable. N'importe qui avec le lien peut la lire.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Partager la lecture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 460, height: shareURL == nil ? 340 : 430)
        #endif
    }

    // MARK: - Not yet published

    @ViewBuilder private var unpublished: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "lock").foregroundStyle(Theme.inkFaint)
                Text("Pas encore partagée").font(.headline).foregroundStyle(.white)
            }
            Text("Publie « \(play.title.isEmpty ? "cette pièce" : play.title) » pour obtenir un lien de lecture web.")
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                run { try await Publish.publish(play, context: context) }
            } label: {
                Label("Publier — lecture seule", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy)
            .overlay { if busy { ProgressView().controlSize(.small) } }
        }
    }

    // MARK: - Published

    @ViewBuilder private func published(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.jade)
                Text("Publiée").font(.headline).foregroundStyle(.white)
                if busy { Spacer(); ProgressView().controlSize(.small) }
            }

            FieldGroup("Lien de lecture") {
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(Theme.gelBright)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.desk, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.rule))

                HStack(spacing: 8) {
                    Button { copy(url.absoluteString) } label: {
                        Label(justCopied ? "Copié" : "Copier", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    Button { openURL(url) } label: {
                        Label("Ouvrir", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered)
            }

            Divider().overlay(Theme.rule)

            HStack {
                Button { run { _ = try await Publish.publish(play, context: context) } } label: {
                    Label("Mettre à jour", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
                Spacer()
                Button(role: .destructive) { run { try await Publish.unpublish(play, context: context) } } label: {
                    Label("Dépublier", systemImage: "trash")
                }
                .disabled(busy)
            }
            .buttonStyle(.bordered)

            Text("« Mettre à jour » republie la version actuelle sous le même lien.")
                .font(.caption).foregroundStyle(Theme.inkFaint)
        }
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
