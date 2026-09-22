import SwiftUI

/// « Notes » — what readers wrote on the shared reading, line by line, with the
/// owner's controls: open/close notes, reply, mark resolved, hide, and jump to
/// the line in the script.
struct NotesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    @ObservedObject var notes: NotesStore
    /// Opened from a line's margin badge: that line comes first, with a composer.
    var focusElementID: String?
    var onJump: (UUID) -> Void
    var onPublish: () -> Void

    @AppStorage("notes.authorName") private var authorName = ""
    @State private var showResolved = false

    private struct LineGroup: Identifiable {
        let id: String
        let element: Element
        let threads: [NoteThread]
    }

    private var visible: [NoteThread] { notes.threads.filter { showResolved || !$0.resolved } }

    private var groups: [LineGroup] {
        let byEl = Dictionary(grouping: visible.filter { !$0.detached && $0.root.elementID != Notes.general }, by: \.root.elementID)
        var out = play.elementList.compactMap { el -> LineGroup? in
            let id = el.id.uuidString
            let ts = byEl[id] ?? []
            return ts.isEmpty && id != focusElementID ? nil : LineGroup(id: id, element: el, threads: ts)
        }
        if let f = focusElementID, let i = out.firstIndex(where: { $0.id == f }) { out.insert(out.remove(at: i), at: 0) }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    status
                    if notes.phase == .ready, notes.meta.commentsOpen || !notes.threads.isEmpty { content }
                    if let e = notes.actionError {
                        Text(e).font(.callout).foregroundStyle(Theme.rose)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 520, height: 680)
        #endif
        .task { await notes.refresh(); notes.markSeen() }
        .onAppear { if authorName.isEmpty { authorName = CollabAuth.shared.person?.name ?? play.author } }
    }

    // MARK: status

    @ViewBuilder private var status: some View {
        switch notes.phase {
        case .idle, .loading:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Je regarde s'il y a des notes…").foregroundStyle(Theme.inkFaint) }
        case .unpublished:
            VStack(alignment: .leading, spacing: 12) {
                Label("Pas encore partagée", systemImage: "lock").font(.headline).foregroundStyle(.white)
                Text("Les notes se laissent sur la lecture web. Partage d'abord la pièce, puis ouvre-la aux notes.")
                    .foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                Button { dismiss(); onPublish() } label: { Label("Partager la lecture…", systemImage: "globe").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.icloud").foregroundStyle(Theme.amber)
                Button("Réessayer") { Task { await notes.refresh() } }.buttonStyle(.bordered)
            }
        case .ready where notes.isShared:
            FieldGroup("Notes") {
                Text(notes.canPost
                     ? "Tout le monde autour de la pièce voit les notes, en direct. Touche une ligne du texte pour en laisser une."
                     : "Tu vois les notes en direct. Ton rôle (Lire) ne permet pas d'en laisser.")
                    .font(.callout).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                if notes.canPost {
                    HStack(spacing: 8) {
                        Text("Tu signes").font(.callout).foregroundStyle(Theme.inkFaint)
                        TextField("Ton nom", text: $authorName).sheetField()
                    }
                }
            }
        case .ready:
            FieldGroup("Notes des lecteurs") {
                Toggle(isOn: Binding(get: { notes.meta.commentsOpen }, set: { v in Task { await notes.setOpen(v) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ouvrir la lecture aux notes").foregroundStyle(.white)
                        Text("Quiconque a le lien peut lire les notes. Pour en laisser une, il faut se connecter avec un identifiant Apple.")
                            .font(.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.gel)
                if notes.meta.commentsOpen {
                    HStack(spacing: 8) {
                        Text("Tu signes").font(.callout).foregroundStyle(Theme.inkFaint)
                        TextField("Ton nom", text: $authorName).sheetField()
                    }
                }
            }
        }
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        let c = Notes.counts(notes.threads)
        HStack {
            Text("Ouvertes : \(c.open) · Réglées : \(c.resolved)").font(.callout).foregroundStyle(Theme.inkFaint)
            Spacer()
            if c.resolved > 0 {
                Button(showResolved ? "Cacher les réglées" : "Voir les réglées") { showResolved.toggle() }
                    .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(Theme.gelBright)
            }
        }

        if groups.isEmpty && visible.isEmpty {
            Text("Aucune note pour l'instant. Envoie le lien de lecture — les notes paraîtront ici et dans la marge du texte.")
                .foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }

        ForEach(groups) { g in
            VStack(alignment: .leading, spacing: 10) {
                Button { dismiss(); onJump(g.element.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(excerpt(g.element)).font(.callout.weight(.semibold)).foregroundStyle(.white)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.forward.square").foregroundStyle(Theme.gelBright)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Ouvrir dans le texte"))
                ForEach(g.threads) { ThreadCard(thread: $0, notes: notes, authorName: authorName) }
                if g.id == focusElementID, notes.meta.commentsOpen, notes.canPost {
                    NoteComposer(placeholder: "Une note sur cette ligne…", submit: "Publier") { body in
                        await notes.post(elementID: g.id, body: body, authorName: authorName)
                    }
                }
            }
        }

        FieldGroup("Notes générales") {
            ForEach(Notes.threads(visible, for: Notes.general)) { ThreadCard(thread: $0, notes: notes, authorName: authorName) }
            if notes.meta.commentsOpen, notes.canPost {
                NoteComposer(placeholder: "Une note sur la pièce dans son ensemble…", submit: "Publier") { body in
                    await notes.post(elementID: Notes.general, body: body, authorName: authorName)
                }
            }
        }

        let detached = visible.filter(\.detached)
        if !detached.isEmpty {
            FieldGroup("Notes détachées") {
                Text("Leur ligne a été coupée ou réécrite depuis. Elles restent ici pour mémoire.")
                    .font(.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                ForEach(detached) { ThreadCard(thread: $0, notes: notes, authorName: authorName) }
            }
        }
    }

    private func excerpt(_ el: Element) -> String {
        let text = (el.text ?? el.label ?? "").replacingOccurrences(of: "\n", with: " ")
        let short = text.count > 90 ? String(text.prefix(90)) + "…" : text
        if el.kind == .cue, let who = play.character(id: el.characterID)?.name { return "\(who) — \(short)" }
        return short.isEmpty ? el.kind.rawValue.uppercased() : short
    }
}

// MARK: - Thread card

private struct ThreadCard: View {
    let thread: NoteThread
    @ObservedObject var notes: NotesStore
    let authorName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if thread.rootDeleted {
                Text("La note d'origine a été supprimée.").font(.caption).foregroundStyle(Theme.inkFaint)
            }
            if let q = thread.root.quote, !q.isEmpty {
                Text("« \(q) »").font(.callout).foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.gel.opacity(0.6)).frame(width: 2) }
            }
            ForEach(Array(thread.all.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider().overlay(Theme.rule) }
                NoteRow(comment: c, isRoot: i == 0, hasReplies: !thread.replies.isEmpty, notes: notes)
            }
            HStack(spacing: 14) {
                if thread.resolved {
                    Label("Réglée", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.jade)
                    if notes.canReopen(thread) { Button("Rouvrir") { Task { await notes.setResolved(thread, false) } } }
                } else if thread.rootDeleted || notes.rights(thread.root).resolve {
                    Button("Marquer réglée") { Task { await notes.setResolved(thread, true) } }
                }
            }
            .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.gelBright)

            if !thread.resolved, notes.meta.commentsOpen, notes.canPost {
                NoteComposer(placeholder: "Répondre…", submit: "Répondre", compact: true) { body in
                    await notes.post(elementID: thread.root.elementID, body: body,
                                     parentID: thread.rootDeleted ? thread.root.parentID : thread.root.id, authorName: authorName)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(thread.resolved ? Theme.rule : Theme.gel.opacity(0.35)))
        .opacity(thread.resolved ? 0.75 : 1)
    }
}

private struct NoteRow: View {
    let comment: PlayComment
    let isRoot: Bool
    let hasReplies: Bool
    @ObservedObject var notes: NotesStore
    @State private var confirming: Confirm?
    private enum Confirm: Identifiable { case remove, hide; var id: Self { self } }

    var body: some View {
        let rights = notes.rights(comment)
        // Deleting a root that has replies would orphan them; resolve it instead.
        let removable = rights.remove && !(isRoot && hasReplies)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(comment.authorName).font(.callout.weight(.semibold)).foregroundStyle(.white)
                if comment.creator == notes.meta.owner {
                    Text("auteur·rice").font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.gel.opacity(0.2), in: Capsule()).foregroundStyle(Theme.gelBright)
                }
                Text(comment.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 0)
                if removable || rights.hide {
                    Menu {
                        if removable { Button("Supprimer", systemImage: "trash", role: .destructive) { confirming = .remove } }
                        if rights.hide { Button("Masquer pour tout le monde", systemImage: "eye.slash") { confirming = .hide } }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.inkFaint).frame(width: 24, height: 18) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            Text(comment.body).font(.body).foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(confirming == .hide ? "Masquer cette note pour tout le monde ?" : "Supprimer ta note ? C'est définitif.",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button(confirming == .hide ? "Masquer" : "Supprimer", role: .destructive) {
                let what = confirming; confirming = nil
                Task { if what == .hide { await notes.hide(comment) } else { await notes.remove(comment) } }
            }
            Button("Annuler", role: .cancel) { confirming = nil }
        }
    }
}

// MARK: - Composer

private struct NoteComposer: View {
    let placeholder: LocalizedStringKey
    let submit: LocalizedStringKey
    var compact = false
    let send: (String) async -> Bool

    @State private var text = ""
    @State private var busy = false

    private var valid: Bool { if case .success = Notes.validBody(text) { return true }; return false }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(compact ? 1...6 : 2...8)
                .sheetField()
            if !text.isEmpty {
                HStack {
                    if text.count > Notes.maxBody {
                        Text("C'est trop long (2000 caractères au plus).").font(.caption).foregroundStyle(Theme.rose)
                    }
                    Spacer()
                    Button(submit) {
                        busy = true
                        Task { if await send(text) { text = "" }; busy = false }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(!valid || busy)
                }
            }
        }
    }
}

/// The small gel capsule that says "n open notes here" — in the script's margin
/// and on the toolbar button.
struct NoteBadge: View {
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill").font(.system(size: 9))
            Text("\(count)").font(.system(size: 11, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.gel, in: Capsule()).foregroundStyle(.white)
        .accessibilityLabel(Text("\(count) notes ouvertes"))
    }
}

/// The margin badge with a preview: HOVER shows the thread(s) in a popover (Mac,
/// iPad with a pointer); a single tap pins the same preview (that is how it works
/// on an iPhone); a DOUBLE tap opens the full Notes screen to reply or edit.
struct NoteBadgeHover: View {
    let count: Int
    let threads: [NoteThread]
    var open: () -> Void

    @State private var hovering = false
    @State private var pinned = false
    @State private var hoverTask: Task<Void, Never>?

    private var shown: Binding<Bool> {
        Binding(get: { pinned || hovering }, set: { if !$0 { pinned = false; hovering = false } })
    }

    var body: some View {
        NoteBadge(count: count)
            .contentShape(Capsule())
            .onTapGesture(count: 2) { dismiss(); open() }
            .onTapGesture { pinned.toggle() }
            .onHover { hover(entered: $0, delay: 350) }
            .popover(isPresented: shown, arrowEdge: .leading) {
                NotePreview(threads: threads, onOpen: { dismiss(); open() })
                    // Keep it while the pointer travels from the badge into the popover.
                    .onHover { hover(entered: $0, delay: 0) }
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityHint(Text("Touche deux fois pour ouvrir les notes"))
    }

    /// A short delay before showing (a pointer just passing by shouldn't pop
    /// anything) and a grace period before hiding (so the popover can be reached).
    private func hover(entered: Bool, delay ms: Int) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(entered ? ms : 300))
            if !Task.isCancelled { hovering = entered }
        }
    }

    private func dismiss() { hoverTask?.cancel(); pinned = false; hovering = false }
}

/// What a badge shows before you open it: each open thread's first note, how
/// many replies it has, and one button to the full screen.
struct NotePreview: View {
    let threads: [NoteThread]
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(threads.prefix(3).enumerated()), id: \.element.id) { i, t in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(t.root.authorName).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        Text(t.root.createdAt, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(Theme.inkFaint)
                        Spacer(minLength: 8)
                        if i == 0 {
                            // One icon, top right — a full-width text button looked stretched
                            // and misaligned in the popover on the iPad (Jac, 2026-09-22).
                            Button(action: onOpen) {
                                Image(systemName: "arrowshape.turn.up.left.circle.fill")
                                    .font(.system(size: 20)).foregroundStyle(Theme.gelBright)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Ouvrir · répondre"))
                            .help(Text("Ouvrir · répondre"))
                        }
                    }
                    if let q = t.root.quote, !q.isEmpty {
                        Text("« \(q) »").font(.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                    }
                    Text(t.root.body).font(.callout).foregroundStyle(.white.opacity(0.92)).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !t.replies.isEmpty {
                        Text(t.replies.count == 1 ? "1 réponse" : "\(t.replies.count) réponses")
                            .font(.caption2).foregroundStyle(Theme.gelBright)
                    }
                }
            }
            if threads.count > 3 {
                Text("… et \(threads.count - 3) de plus").font(.caption2).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(Theme.deskLight)
    }
}
