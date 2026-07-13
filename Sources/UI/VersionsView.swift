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
            List {
                Section {
                    HStack {
                        TextField("Nom de la version (ex. « 1er jet »)", text: $name)
                        Button("Enregistrer") { Versions.save(play, name: name, context: context); name = "" }
                    }
                }
                Section("Versions") {
                    if versions.isEmpty {
                        Text("Aucune version. Fige un état pour y revenir plus tard.").foregroundStyle(.secondary)
                    }
                    ForEach(versions) { v in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(v.name).font(.headline)
                                Text(v.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restaurer") { restoreCandidate = v }.buttonStyle(.bordered)
                        }
                    }
                    .onDelete { idx in idx.map { versions[$0] }.forEach(context.delete) }
                }
            }
            .navigationTitle("Versions")
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
        .frame(width: 440, height: 520)
        #endif
    }
}
