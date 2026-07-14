import SwiftUI
import SwiftData

/// "À propos de la pièce" — a single card holding everything about the play:
/// editable metadata (title, subtitle, author, logline, languages, première,
/// private notes) over a read-only panel of computed figures (acts, scenes,
/// cast, lines, words, runtime). Opened by double-clicking a play in the sidebar.
struct PlayInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play

    private var totals: Stats.PlayTotals { Stats.castStats(play).totals }
    private var actCount: Int {
        // A play with scenes but no explicit ACTE markers still reads as one act.
        totals.actCount == 0 && totals.sceneCount > 0 ? 1 : totals.actCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identity
                    figures
                    languages
                    privateNotes
                    history
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("À propos de la pièce")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .onChange(of: play.title) { _, _ in play.touch() }
        .onChange(of: play.subtitle) { _, _ in play.touch() }
        .onChange(of: play.author) { _, _ in play.touch() }
        .onChange(of: play.logline) { _, _ in play.touch() }
        #if os(macOS)
        .frame(width: 480, height: 660)
        #endif
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldGroup("Titre") {
                TextField("Titre", text: $play.title).sheetField()
            }
            FieldGroup("Sous-titre") {
                TextField("p. ex. pièce en deux actes", text: $play.subtitle).sheetField()
            }
            FieldGroup("Autrice / auteur") {
                TextField("Nom", text: $play.author).sheetField()
            }
            FieldGroup("Résumé") {
                TextField("Une phrase ou deux sur la pièce.", text: $play.logline, axis: .vertical)
                    .lineLimit(2...5)
                    .sheetField()
                Text("Publié avec la lecture web, sous le titre.")
                    .font(.caption2).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    // MARK: - Figures

    private var figures: some View {
        FieldGroup("La pièce en chiffres") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                StatCell(value: "\(actCount)", label: actCount == 1 ? "Acte" : "Actes")
                StatCell(value: "\(totals.sceneCount)", label: totals.sceneCount == 1 ? "Scène" : "Scènes")
                StatCell(value: "\(play.characterList.count)", label: play.characterList.count == 1 ? "Personnage" : "Personnages")
                StatCell(value: "\(totals.totalLines)", label: totals.totalLines == 1 ? "Réplique" : "Répliques")
                StatCell(value: "\(totals.spokenWords)", label: "Mots")
                StatCell(value: Stats.formatRuntime(totals.runtimeMinutes, play.lang), label: "Durée")
            }
        }
    }

    // MARK: - Languages

    private var languages: some View {
        FieldGroup("Langues") {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Originale").font(.caption2).foregroundStyle(Theme.inkFaint)
                    Picker("", selection: $play.lang) {
                        ForEach(Lang.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Surtitres").font(.caption2).foregroundStyle(Theme.inkFaint)
                    Picker("", selection: $play.altLang) {
                        Text("Aucune").tag(Optional<Lang>.none)
                        ForEach(Lang.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Private notes

    private var privateNotes: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldGroup("Création") {
                TextField("Où et quand la pièce a été créée.", text: $play.premiere, axis: .vertical)
                    .lineLimit(1...3)
                    .sheetField()
            }
            FieldGroup("Notes") {
                TextField("Intentions, pistes, rappels…", text: $play.notes, axis: .vertical)
                    .lineLimit(3...10)
                    .sheetField()
                Label("Privées — jamais publiées ni exportées.", systemImage: "lock")
                    .font(.caption2).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    // MARK: - History

    private var history: some View {
        HStack {
            dateColumn("Créée", play.createdAt)
            Spacer()
            dateColumn("Modifiée", play.updatedAt)
        }
        .padding(.top, 2)
    }

    private func dateColumn(_ label: LocalizedStringKey, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.bold)).kerning(1.0)
                .foregroundStyle(Theme.inkFaint).textCase(.uppercase)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.callout).foregroundStyle(Theme.inkSoft)
        }
    }
}

/// One read-only figure cell in the "chiffres" grid.
private struct StatCell: View {
    let value: String
    let label: LocalizedStringKey
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.caption2).foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule, lineWidth: 1))
    }
}
