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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FieldGroup("Langue de la pièce") {
                        Picker("", selection: langBinding) {
                            Text("Français").tag(Lang.fr)
                            Text("English").tag(Lang.en)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    FieldGroup("Ajouter un personnage") {
                        HStack(spacing: 10) {
                            TextField("Nom", text: $draft).onSubmit(addCharacter).sheetField()
                            Button(action: addCharacter) { Image(systemName: "plus") }
                                .buttonStyle(.borderedProminent)
                                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    FieldGroup("Distribution") {
                        if play.characterList.isEmpty {
                            Text("Aucun personnage pour l'instant.")
                                .font(.callout).foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(play.characterList) { c in
                                    CharacterCard(play: play, character: c,
                                                  stat: stats.first { $0.character.id == c.id },
                                                  onDelete: { Editing.removeCharacter(play, c, context: context) })
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Distribution")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 580)
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

private struct CharacterCard: View {
    @Bindable var play: Play
    @Bindable var character: Character
    let stat: Stats.CastStat?
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(Theme.castSwatches, id: \.self) { hex in
                        Button { character.colorHex = hex; play.touch() } label: {
                            Label(hex, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    Circle().fill(Color(hexString: character.colorHex)).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white.opacity(0.15)))
                }
                .menuStyle(.borderlessButton).fixedSize()

                TextField("Nom", text: nameBinding).textFieldStyle(.plain)
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                if let s = stat {
                    Text("\(s.lines) rép · \(s.scenes) sc").font(.caption2).foregroundStyle(Theme.inkFaint)
                }
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(Theme.inkFaint).font(.caption)
            }
            TextField("Qui est-ce ? (facultatif)", text: noteBinding)
                .textFieldStyle(.plain).font(.subheadline).foregroundStyle(Theme.inkFaint)
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.caption2).foregroundStyle(Theme.inkFaint)
                TextField("Voix ElevenLabs (id, facultatif)", text: voiceBinding)
                    .textFieldStyle(.plain).font(.caption).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(12)
        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hexString: character.colorHex))
                .frame(width: 3).padding(.vertical, 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
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
