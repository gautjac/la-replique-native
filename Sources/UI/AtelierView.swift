import SwiftUI
import SwiftData

struct AtelierView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    var onOpenPlay: (UUID) -> Void

    enum Tool: String, CaseIterable, Identifiable {
        case relance, etsi, dramaturgie, voix, traduire, dramaturge
        var id: String { rawValue }
        var label: String {
            switch self {
            case .relance: return String(localized: "Relancer"); case .etsi: return String(localized: "Et si…")
            case .dramaturgie: return String(localized: "Dramaturgie"); case .voix: return String(localized: "Voix"); case .traduire: return String(localized: "Traduire")
            case .dramaturge: return String(localized: "Demander")
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

    // Dramaturge thread — kept while the sheet is open; a new play = a new sheet.
    struct Turn: Identifiable { let id = UUID(); let role: String; let text: String; var followups: [String] = [] }
    @State private var thread: [Turn] = []
    @State private var question = ""
    @State private var wholePlay = true
    @FocusState private var questionFocused: Bool

    private var sceneBlocks: [Editing.Block] { Editing.decompose(play).blocks.filter { !$0.isAct } }
    private var selectedEls: [Element] {
        if let id = sceneID, let b = sceneBlocks.first(where: { $0.id == id }) { return b.els }
        return sceneBlocks.first?.els ?? play.elementList
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !AppKeys.hasAnthropic && !Self.uiPreview {
                        keyPrompt
                    } else {
                        toolPicker
                        contextControls
                        if tool == .dramaturge {
                            dramaturgePane
                        } else {
                            runButton
                        }
                        if busy { HStack { ProgressView(); Text(stage).foregroundStyle(.secondary) } }
                        if let error { Text(error).foregroundStyle(Theme.rose) }
                        results
                        Text("L'Atelier propose — rien n'entre dans ta pièce sans ton geste.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }.padding(18)
            }
            .background(Theme.deskLight)
            .navigationTitle("Atelier")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .sheet(isPresented: $showKeys) { KeySetupView() }
        }
        #if os(macOS)
        .frame(width: 580, height: 700)
        #endif
    }

    /// `ATELIER_PREVIEW=1` in the environment shows the tools without a key (UI checks
    /// in a Debug build); every call then fails with the normal "add your key" error.
    static let uiPreview = ProcessInfo.processInfo.environment["ATELIER_PREVIEW"] == "1"

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
        if tool == .dramaturge {
            Picker("Sur quoi ?", selection: $wholePlay) {
                Text("Toute la pièce").tag(true)
                Text("Une scène").tag(false)
            }.pickerStyle(.segmented)
        }
        if tool != .traduire && (tool != .dramaturge || !wholePlay) {
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

    // MARK: Dramaturge pane

    private var starters: [String] {
        var list: [String] = []
        if let n = play.characterList.first?.name {
            list.append(String(format: String(localized: "Qu'est-ce que %@ veut vraiment ici, et qu'est-ce qui l'en empêche ?"), n))
        }
        list.append(String(localized: "Où la scène tourne-t-elle ? Où est-ce qu'elle mollit ?"))
        list.append(String(localized: "Ma fin est-elle gagnée, ou seulement annoncée ?"))
        list.append(String(localized: "Quel personnage est le plus faible, et pourquoi ?"))
        return list
    }

    private func chips(_ title: LocalizedStringKey, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            FlowChips(items: items, disabled: busy) { q in Task { await ask(q) } }
        }
    }

    private var dramaturgePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pose une question sur ta pièce — un personnage, une scène qui mollit, une fin. Une lecture, pas un verdict.")
                .font(.callout).foregroundStyle(.secondary)
            if thread.isEmpty { chips("Pour commencer", starters) }
            ForEach(thread) { turn in
                if turn.role == "user" {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Toi").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text(turn.text).font(.callout).foregroundStyle(.white)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10)).padding(.leading, 24)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Le dramaturge").font(.caption2.weight(.bold)).foregroundStyle(Theme.gelBright); Spacer(); draftBadge }
                        ForEach(Array(AnswerText.blocks(turn.text).enumerated()), id: \.offset) { _, b in
                            switch b {
                            case .paragraph(let t): Text(t).font(.callout).foregroundStyle(.white)
                            case .bullets(let items):
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                                        HStack(alignment: .top, spacing: 6) { Text("•"); Text(it) }.font(.callout).foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gel.opacity(0.4))).padding(.trailing, 24)
                }
            }
            if !busy, let last = thread.last, last.role == "assistant", !last.followups.isEmpty { chips("Et ensuite…", last.followups) }
            VStack(spacing: 6) {
                TextField("Ta question au dramaturge…", text: $question, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).focused($questionFocused)
                    .onSubmit { Task { await ask(question) } }
                HStack {
                    if !thread.isEmpty {
                        Button("Nouvelle conversation") { thread = []; error = nil }.font(.caption).disabled(busy)
                    }
                    Spacer()
                    Button("Envoyer") { Task { await ask(question) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10).background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func ask(_ q: String) async {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        let history = thread.map { DramaturgeTurn(role: $0.role, text: $0.text) }
        thread.append(Turn(role: "user", text: text))
        question = ""; error = nil; busy = true; stage = String(localized: "je relis la pièce…")
        defer { busy = false; questionFocused = true }
        do {
            let els = wholePlay ? play.elementList : selectedEls
            let res = try await Atelier.dramaturge(lang: play.lang, question: text,
                                                   play: Atelier.scriptText(els, play: play), title: play.title,
                                                   cast: play.characterList.map(\.name), history: history)
            thread.append(Turn(role: "assistant", text: res.answer, followups: res.followups))
        } catch is AtelierError {
            thread.removeLast(); question = text
            error = "Ajoute d'abord ta clé Claude."
        } catch {
            thread.removeLast(); question = text
            self.error = "Le service n'a pas répondu. Réessaie dans un instant."
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
        error = nil; busy = true; stage = String(localized: "je lis la scène…")
        defer { busy = false }
        do {
            let sceneText = Atelier.scriptText(selectedEls, play: play)
            let names = play.characterList.map(\.name)
            switch tool {
            case .relance:
                let name = play.character(id: charID)?.name ?? names.first ?? "?"
                stage = String(localized: "je cherche la voix…")
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
            case .dramaturge:
                break // handled by ask(_:) from the pane
            case .traduire:
                stage = String(localized: "je traduis…")
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

/// Answer text → paragraphs and "- " bullet lists (mirrors the web helper).
enum AnswerText {
    enum Block: Equatable { case paragraph(String), bullets([String]) }
    static func blocks(_ answer: String) -> [Block] {
        var out: [Block] = []
        for chunk in answer.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            var para: [String] = [], items: [String] = []
            for raw in chunk.components(separatedBy: "\n") {
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.isEmpty { continue }
                if l.hasPrefix("- ") || l.hasPrefix("• ") {
                    if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
                    items.append(String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                } else {
                    if !items.isEmpty { out.append(.bullets(items)); items = [] }
                    para.append(l)
                }
            }
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))) }
            if !items.isEmpty { out.append(.bullets(items)) }
        }
        return out
    }
}

/// Wrapping row of tappable question chips.
struct FlowChips: View {
    let items: [String]
    var disabled = false
    let onTap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, q in
                Button { onTap(q) } label: {
                    Text(q).font(.caption).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.deskLight, in: Capsule())
                        .overlay(Capsule().stroke(Theme.gel.opacity(0.35)))
                }
                .buttonStyle(.plain).disabled(disabled)
            }
        }
    }
}
