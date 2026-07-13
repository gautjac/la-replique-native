import SwiftUI
import SwiftData

struct AtelierView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    var onOpenPlay: (UUID) -> Void

    enum Tool: String, CaseIterable, Identifiable {
        case relance, etsi, dramaturgie, voix, traduire
        var id: String { rawValue }
        var label: String {
            switch self {
            case .relance: return "Relancer"; case .etsi: return "Et si…"
            case .dramaturgie: return "Dramaturgie"; case .voix: return "Voix"; case .traduire: return "Traduire"
            }
        }
    }

    @State private var tool: Tool = .relance
    @State private var sceneID: UUID?
    @State private var charID: String?
    @State private var busy = false
    @State private var stage = ""
    @State private var error: String?
    @State private var showKeys = false

    @State private var relanceRes: RelanceRes?
    @State private var dramRes: DramaturgieRes?
    @State private var voixRes: VoixRes?
    @State private var etsiRes: EtSiRes?

    private var sceneBlocks: [Editing.Block] { Editing.decompose(play).blocks.filter { !$0.isAct } }
    private var selectedEls: [Element] {
        if let id = sceneID, let b = sceneBlocks.first(where: { $0.id == id }) { return b.els }
        return sceneBlocks.first?.els ?? play.elementList
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !AppKeys.hasAnthropic {
                        keyPrompt
                    } else {
                        toolPicker
                        contextControls
                        runButton
                        if busy { HStack { ProgressView(); Text(stage).foregroundStyle(.secondary) } }
                        if let error { Text(error).foregroundStyle(Theme.rose) }
                        results
                        Text("L'Atelier propose — rien n'entre dans ta pièce sans ton geste.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }.padding(18)
            }
            .navigationTitle("Atelier")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .sheet(isPresented: $showKeys) { KeySetupView() }
        }
        #if os(macOS)
        .frame(width: 500, height: 640)
        #endif
    }

    private var keyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "key").font(.largeTitle).foregroundStyle(Theme.gel)
            Text("Ajoute ta clé Claude pour utiliser l'Atelier.").multilineTextAlignment(.center)
            Button("Ajouter ma clé") { showKeys = true }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private var toolPicker: some View {
        Picker("Outil", selection: $tool) {
            ForEach(Tool.allCases) { Text($0.label).tag($0) }
        }.pickerStyle(.segmented)
    }

    @ViewBuilder private var contextControls: some View {
        if tool != .traduire {
            Picker("Scène", selection: $sceneID) {
                Text("Scène courante").tag(UUID?.none)
                ForEach(sceneBlocks) { b in Text(b.heading.label ?? "Scène").tag(Optional(b.id)) }
            }
        }
        if tool == .relance || tool == .voix {
            Picker(tool == .relance ? "Pour qui ?" : "Quel personnage ?", selection: $charID) {
                Text("—").tag(String?.none)
                ForEach(play.characterList) { c in Text(c.name).tag(Optional(c.id.uuidString)) }
            }
        }
        if tool == .traduire {
            HStack {
                Text(play.lang.rawValue.uppercased()).bold()
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.gel)
                Text((play.lang == .fr ? "EN" : "FR")).bold().foregroundStyle(Theme.gelBright)
            }
        }
    }

    private var runButton: some View {
        Button { Task { await run() } } label: {
            Text("Demander").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(busy)
    }

    @ViewBuilder private var results: some View {
        if let r = relanceRes, tool == .relance { relanceResult(r) }
        if let r = dramRes, tool == .dramaturgie { readResult(r.read, r.points.map { ($0.kind, $0.text) }) }
        if let r = voixRes, tool == .voix { readResult(r.read, r.points.map { ($0.excerpt, $0.note) }) }
        if let r = etsiRes, tool == .etsi {
            VStack(alignment: .leading, spacing: 8) {
                draftBadge
                ForEach(r.ideas) { idea in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(idea.premise).font(.callout.weight(.medium)).foregroundStyle(.white)
                        Text(idea.why).font(.caption).foregroundStyle(.secondary)
                    }.padding(10).background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var draftBadge: some View {
        Label("ébauche · à toi de décider", systemImage: "circle.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.gelBright)
    }

    private func relanceResult(_ r: RelanceRes) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            draftBadge
            VStack(alignment: .leading, spacing: 4) {
                Text((play.character(id: charID)?.name ?? "?").uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(Color(hexString: play.character(id: charID)?.colorHex))
                if let p = r.parenthetical, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary) }
                Text(r.line).font(.body).foregroundStyle(Theme.ink)
            }.padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Insérer dans la scène") { insertRelance(r) }.buttonStyle(.borderedProminent)
                Button("Une autre") { Task { await run() } }.buttonStyle(.bordered)
            }
        }
    }

    private func readResult(_ read: String, _ points: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            draftBadge
            Text(read).font(.callout).foregroundStyle(.white)
                .padding(12).background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.0).font(.caption.weight(.bold)).foregroundStyle(Theme.gelBright)
                    Text(p.1).font(.caption).foregroundStyle(.secondary)
                }.padding(10).background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Run

    private func run() async {
        error = nil; busy = true; stage = "je lis la scène…"
        defer { busy = false }
        do {
            let sceneText = Atelier.scriptText(selectedEls, play: play)
            let names = play.characterList.map(\.name)
            switch tool {
            case .relance:
                let name = play.character(id: charID)?.name ?? names.first ?? "?"
                stage = "je cherche la voix…"
                relanceRes = try await Atelier.relance(lang: play.lang, scene: sceneText, characterName: name, cast: names)
            case .dramaturgie:
                dramRes = try await Atelier.dramaturgie(lang: play.lang, scene: sceneText)
            case .etsi:
                etsiRes = try await Atelier.etsi(lang: play.lang, scene: sceneText)
            case .voix:
                let cid = charID ?? play.characterList.first?.id.uuidString
                let name = play.character(id: cid)?.name ?? "?"
                let lines = play.elementList.filter { $0.kind == .cue && $0.characterID == cid }.compactMap { $0.text }
                voixRes = try await Atelier.voix(lang: play.lang, characterName: name, lines: lines)
            case .traduire:
                stage = "je traduis…"
                let to: Lang = play.lang == .fr ? .en : .fr
                let items = Translate.buildBundle(play)
                let res = try await Atelier.traduire(from: play.lang, to: to, items: items)
                let np = Translate.makeTranslatedPlay(play, to: to, items: res.items, context: context)
                dismiss(); onOpenPlay(np.id)
            }
        } catch is AtelierError {
            error = "Ajoute d'abord ta clé Claude."
        } catch {
            self.error = "Le service n'a pas répondu. Réessaie dans un instant."
        }
    }

    private func insertRelance(_ r: RelanceRes) {
        let after = selectedEls.last
        let el = Editing.insert(.cue, after: after, play: play, context: context, speaker: charID)
        el.text = r.line
        el.parenthetical = (r.parenthetical?.isEmpty == false) ? r.parenthetical : nil
        relanceRes = nil
    }
}
