import SwiftUI
import SwiftData

// « Historique » — the diary of a shared play — and « Versions » — its named
// snapshots, with a comparison.

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let play: Play
    let session: CollabSession
    @StateObject private var store: HistoryStore
    var onJump: (UUID) -> Void

    init(play: Play, session: CollabSession, onJump: @escaping (UUID) -> Void) {
        self.play = play; self.session = session; self.onJump = onJump
        _store = StateObject(wrappedValue: HistoryStore(playID: session.link.remoteID))
    }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let cal = Calendar.current
        return Dictionary(grouping: store.entries, by: { cal.startOfDay(for: $0.at) })
            .map { (day: $0.key, entries: $0.value.sorted { $0.at > $1.at }) }.sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let recent = session.recentChanges
                    if !recent.isEmpty {
                        FieldGroup("Depuis ta dernière visite") {
                            Text("\(recent.count) lignes touchées par d'autres depuis \(session.since.formatted(.relative(presentation: .named))).")
                                .font(.callout).foregroundStyle(Theme.inkFaint)
                        }
                    }
                    if store.entries.isEmpty {
                        Text("Aucun changement enregistré pour l'instant. Tout ce qui s'écrit ici à partir de maintenant restera dans l'historique.")
                            .foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(days, id: \.day) { d in
                        FieldGroup(LocalizedStringKey(d.day.formatted(date: .long, time: .omitted))) {
                            ForEach(d.entries) { e in HistoryRow(entry: e, play: play, session: session, context: context, onJump: { dismiss(); onJump($0) }) }
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Historique")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 540, height: 640)
        #endif
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let play: Play
    let session: CollabSession
    let context: ModelContext
    var onJump: (UUID) -> Void

    private var element: Element? { UUID(uuidString: entry.elementID).flatMap { id in (play.elements ?? []).first { $0.id == id } } }
    private var canRestore: Bool { session.link.canWrite && (entry.kind == .edit && element != nil || entry.kind == .delete) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(authorColor).frame(width: 8, height: 8)
                Text(entry.name).font(.callout.weight(.semibold)).foregroundStyle(.white)
                Text(verb).font(.callout).foregroundStyle(Theme.inkFaint)
                Spacer()
                Text(when).font(.caption).foregroundStyle(Theme.inkFaint)
            }
            if let who = entry.speaker { Text(who).font(.caption.weight(.bold)).kerning(1).foregroundStyle(Theme.gelBright) }
            switch entry.kind {
            case .edit:
                // Only the verses that changed: the words that went, struck through;
                // the words that came, in the author's colour.
                let before = entry.textBefore ?? "", after = entry.textAfter ?? ""
                if WordDiff.hasChange(before, after) {
                    Text(WordDiff.attributed(before, after, author: authorColor))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Le texte est revenu au même.").font(.callout).foregroundStyle(Theme.inkFaint)
                }
            case .delete:
                if let b = entry.textBefore, !b.isEmpty {
                    Text(b).font(.callout).foregroundStyle(Theme.rose.opacity(0.9)).strikethrough().fixedSize(horizontal: false, vertical: true)
                }
            case .add:
                if let a = entry.textAfter, !a.isEmpty {
                    Text(a).font(.callout).foregroundStyle(authorColor).fixedSize(horizontal: false, vertical: true)
                }
            default: EmptyView()
            }
            HStack(spacing: 14) {
                if element != nil {
                    Button { if let el = element { onJump(el.id) } } label: { Label("Ouvrir dans le texte", systemImage: "arrow.up.forward.square") }
                }
                if canRestore {
                    Button { restore() } label: { Label(entry.kind == .delete ? "Remettre la ligne" : "Restaurer ce texte", systemImage: "arrow.uturn.backward") }
                }
            }
            .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.gelBright)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 10))
    }

    private var authorColor: Color { Color(hexString: PresenceChannel.color(for: entry.uid)) }

    /// A burst of typing shows as a span: « 20:32 – 20:35 ».
    private var when: String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        let a = entry.from.formatted(f), b = entry.at.formatted(f)
        return a == b ? b : "\(a) – \(b)"
    }

    private var verb: LocalizedStringKey {
        switch entry.kind {
        case .edit: return "a retouché une ligne"
        case .add: return "a ajouté une ligne"
        case .delete: return "a supprimé une ligne"
        case .move: return "a déplacé une ligne"
        case .cast: return "a changé la distribution"
        case .info: return "a changé le titre ou l'en-tête"
        }
    }

    /// Restoring is just an edit made by me: it syncs and is logged like any other.
    private func restore() {
        guard let before = entry.before else { return }
        if entry.kind == .delete {
            guard let id = UUID(uuidString: entry.elementID), (play.elements ?? []).first(where: { $0.id == id }) == nil else { return }
            let el = Element(kind: ElementKind(rawValue: before[CollabField.kind] ?? "cue") ?? .cue, order: Int.max)
            el.id = id
            el.characterID = before[CollabField.characterID]; el.text = before[CollabField.text]; el.label = before[CollabField.label]
            el.setting = before[CollabField.setting]; el.synopsis = before[CollabField.synopsis]; el.beatRaw = before[CollabField.beat]
            el.parenthetical = before[CollabField.parenthetical]; el.alt = before[CollabField.alt]
            el.play = play
            context.insert(el)
            // Back where it was, if that neighbourhood still exists.
            let arr = play.elementList
            for (i, e) in arr.enumerated() where e.id != id { e.order = i }
            el.order = arr.count
        } else if let el = element {
            if let t = before[CollabField.text] { el.text = t }
            if let l = before[CollabField.label] { el.label = l }
            if let p = before[CollabField.parenthetical] { el.parenthetical = p }
        }
        play.touch()
    }
}

// MARK: - Versions of a shared play

struct SharedVersionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let play: Play
    let session: CollabSession
    @StateObject private var store: SharedVersionsStore
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var compare: (SharedVersion, SharedVersion?)?
    @State private var restoreCandidate: SharedVersion?

    init(play: Play, session: CollabSession) {
        self.play = play; self.session = session
        _store = StateObject(wrappedValue: SharedVersionsStore(playID: session.link.remoteID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if session.link.canWrite {
                        FieldGroup("Enregistrer une version") {
                            HStack(spacing: 8) {
                                TextField("Lecture du 3 octobre…", text: $name).sheetField().onSubmit(save)
                                Button(action: save) { Image(systemName: "plus") }.buttonStyle(.borderedProminent).disabled(busy)
                            }
                            Text("Une version est une photo de la pièce à cet instant, signée. Compare-la à la version actuelle ou à une autre ; restaure-la au besoin.")
                                .font(.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(Theme.rose) }
                    FieldGroup("Versions") {
                        if store.versions.isEmpty { Text("Aucune version enregistrée.").font(.callout).foregroundStyle(Theme.inkFaint) }
                        ForEach(store.versions) { v in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(v.name).font(.callout.weight(.semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(v.by) · \(v.at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.inkFaint)
                                }
                                HStack(spacing: 12) {
                                    Button("Comparer à maintenant") { compare = (v, nil) }
                                    Menu("Comparer à…") {
                                        ForEach(store.versions.filter { $0.id != v.id }) { o in Button(o.name) { compare = (v, o) } }
                                    }.fixedSize()
                                    if session.link.canWrite { Button("Restaurer") { restoreCandidate = v } }
                                    if v.uid == CollabBackend.uid || session.link.ownerUid == CollabBackend.uid {
                                        Button(role: .destructive) { Task { try? await store.remove(v) } } label: { Image(systemName: "trash") }
                                    }
                                }
                                .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.gelBright)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.desk, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Versions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .sheet(isPresented: Binding(get: { compare != nil }, set: { if !$0 { compare = nil } })) {
                if let (a, b) = compare {
                    VersionDiffView(play: play, from: a, to: b, currentAuthors: session.authorsByLine)
                }
            }
            .alert("Restaurer cette version ?", isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
                Button("Restaurer", role: .destructive) {
                    if let v = restoreCandidate, let doc = SharedVersionsStore.doc(v) {
                        PlayFormat.replaceContent(of: play, with: doc, context: context)   // keeps line ids → notes stay
                        play.touch()
                    }
                    restoreCandidate = nil
                }
                Button("Annuler", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("Le texte actuel sera remplacé pour tout le monde. Enregistre d'abord une version si tu veux pouvoir y revenir.")
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 600)
        #endif
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    private func save() {
        guard let uid = CollabBackend.uid else { return }
        busy = true; error = nil
        let n = name
        Task { @MainActor in
            do {
                try await store.save(play, name: n, by: (uid, session.link.myName.isEmpty ? CollabSession.displayName : session.link.myName), authors: session.authorsByLine)
                name = ""
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// Two states of the play, line by line: additions, deletions, changes, moves —
/// each coloured by whoever last touched the line in the newer state.
struct VersionDiffView: View {
    @Environment(\.dismiss) private var dismiss
    let play: Play
    let from: SharedVersion
    /// nil = compare `from` to the play as it is now.
    let to: SharedVersion?
    let currentAuthors: [String: String]

    private var rows: [PlayDiff.Row] {
        let a = SharedVersionsStore.doc(from)?.elements ?? []
        let b = to.flatMap { SharedVersionsStore.doc($0)?.elements } ?? PlayFormat.aiDoc(from: play, withElementIDs: true).elements
        return PlayDiff.compare(a, b)
    }
    private var authors: [String: String] { to?.authors ?? currentAuthors }

    var body: some View {
        NavigationStack {
            ScrollView {
                let rows = rows
                let s = PlayDiff.summary(rows)
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(from.name) → \(to?.name ?? String(localized: "maintenant"))").font(.headline).foregroundStyle(.white)
                    Text("+\(s.added) · −\(s.removed) · \(s.changed) retouchées · \(s.moved) déplacées").font(.caption).foregroundStyle(Theme.inkFaint)
                    if !rows.contains(where: \.isChange) { Text("Aucune différence.").foregroundStyle(Theme.inkFaint).padding(.top, 8) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        if row.isChange { DiffRowView(row: row, author: row.doc.id.flatMap { authors[$0] }) }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Comparaison")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
    }
}

private struct DiffRowView: View {
    let row: PlayDiff.Row
    let author: String?

    private func text(_ d: ElDoc) -> String { (d.type == "cue" ? (d.character.map { "\($0) — " } ?? "") : "") + (d.text ?? d.label ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tag).font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.2), in: Capsule()).foregroundStyle(color)
                if let author { Text(author).font(.caption).foregroundStyle(Theme.inkFaint) }
            }
            switch row {
            case .removed(let d): Text(text(d)).strikethrough().foregroundStyle(Theme.rose.opacity(0.9))
            case .added(let d), .moved(let d), .same(let d): Text(text(d)).foregroundStyle(.white.opacity(0.92))
            case .changed(let a, let b):
                Text(WordDiff.attributed(text(a), text(b), author: Theme.gelBright)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
    }
    private var tag: LocalizedStringKey {
        switch row { case .added: return "ajoutée"; case .removed: return "supprimée"; case .changed: return "retouchée"; case .moved: return "déplacée"; case .same: return "" }
    }
    private var color: Color {
        switch row { case .added: return Theme.jade; case .removed: return Theme.rose; case .changed: return Theme.gel; case .moved: return Theme.plum; case .same: return Theme.inkFaint }
    }
}
