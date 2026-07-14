import SwiftUI
import SwiftData

struct VersionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    @Query(sort: \Version.createdAt, order: .reverse) private var allVersions: [Version]
    @State private var name = ""
    @State private var restoreCandidate: Version?

    private var versions: [Version] { allVersions.filter { $0.playID == play.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FieldGroup("Nouvelle version") {
                        HStack(spacing: 10) {
                            TextField("Nom (ex. « 1er jet »)", text: $name)
                                .onSubmit(saveIfNamed)
                                .sheetField()
                            Button("Enregistrer", action: saveIfNamed)
                                .buttonStyle(.borderedProminent)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    FieldGroup("Versions enregistrées") {
                        if versions.isEmpty {
                            Text("Aucune version. Fige un état pour y revenir plus tard.")
                                .font(.callout).foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        } else {
                            VStack(spacing: 8) { ForEach(versions, content: versionRow) }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Versions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .alert("Restaurer cette version ?", isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
                Button("Restaurer", role: .destructive) {
                    if let v = restoreCandidate { Versions.restore(v, into: play, context: context) }
                    restoreCandidate = nil
                }
                Button("Annuler", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("L'état actuel de la pièce est remplacé.")
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 540)
        #endif
    }

    private func saveIfNamed() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Versions.save(play, name: n, context: context)
        name = ""
    }

    private func versionRow(_ v: Version) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name.isEmpty ? "Sans nom" : v.name).font(.headline).foregroundStyle(.white)
                Text(v.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button("Restaurer") { restoreCandidate = v }.buttonStyle(.bordered).controlSize(.small)
            Button { context.delete(v) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(Theme.inkFaint)
        }
        .padding(12)
        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
    }
}
