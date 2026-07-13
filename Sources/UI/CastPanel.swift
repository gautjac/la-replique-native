import SwiftUI
import SwiftData

struct CastPanel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    @State private var draft = ""

    private var stats: [Stats.CastStat] { Stats.castStats(play).perCharacter }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Langue de la pièce", selection: langBinding) {
                        Text("FR").tag(Lang.fr); Text("EN").tag(Lang.en)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    HStack {
                        TextField("Ajouter un personnage", text: $draft)
                            .onSubmit(addCharacter)
                        Button(action: addCharacter) { Image(systemName: "plus.circle.fill") }
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Distribution") {
                    ForEach(play.characterList) { c in
                        CharacterRow(play: play, character: c,
                                     stat: stats.first { $0.character.id == c.id })
                    }
                    .onDelete { idx in
                        idx.map { play.characterList[$0] }.forEach { Editing.removeCharacter(play, $0, context: context) }
                    }
                    if play.characterList.isEmpty {
                        Text("Aucun personnage pour l'instant.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Distribution")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }

    private var langBinding: Binding<Lang> {
        Binding(get: { play.lang }, set: { play.lang = $0; play.touch() })
    }

    private func addCharacter() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Editing.addCharacter(play, name: name.uppercased(), context: context)
        draft = ""
    }
}

private struct CharacterRow: View {
    @Bindable var play: Play
    @Bindable var character: Character
    let stat: Stats.CastStat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(Theme.castSwatches, id: \.self) { hex in
                        Button { character.colorHex = hex; play.touch() } label: {
                            Label(hex, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    Circle().fill(Color(hexString: character.colorHex)).frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton).fixedSize()

                TextField("Nom", text: nameBinding).textFieldStyle(.plain)
                    .font(.headline)
            }
            TextField("Qui est-ce ? (facultatif)", text: noteBinding)
                .font(.caption).foregroundStyle(.secondary).textFieldStyle(.plain)
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.caption2).foregroundStyle(.tertiary)
                TextField("Voix ElevenLabs (id, facultatif)", text: voiceBinding)
                    .font(.caption).foregroundStyle(.secondary).textFieldStyle(.plain)
            }
            if let s = stat {
                Text("\(s.lines) répliques · \(s.scenes) scènes").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var nameBinding: Binding<String> {
        Binding(get: { character.name }, set: { character.name = $0.uppercased(); play.touch() })
    }
    private var noteBinding: Binding<String> {
        Binding(get: { character.note ?? "" }, set: { character.note = $0; play.touch() })
    }
    private var voiceBinding: Binding<String> {
        Binding(get: { character.voiceID ?? "" }, set: { character.voiceID = $0.isEmpty ? nil : $0; play.touch() })
    }
}
