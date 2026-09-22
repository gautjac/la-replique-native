import SwiftUI

/// Hosts a play: the Texte (editor) / Tableau (beat board) toggle, plus the
/// Distribution and Mesures inspectors as sheets.
struct PlayDetailView: View {
    @Bindable var play: Play
    var onOpenPlay: (UUID) -> Void
    /// Non-nil when this is a shared play, live.
    var collab: CollabSession?
    /// Lines other people changed since my last visit (shared plays).
    var recentChanges: [String: LineEdit] = [:]
    @State private var showChanges = false
    @State private var showSharedVersions = false
    @ObservedObject private var presence: PresenceChannel
    @State private var showCollab = false
    @State private var mode: Mode = .script
    @State private var jumpTarget: UUID?
    @State private var showCast = false
    @State private var showMeasures = false
    @State private var showAtelier = false
    @State private var showVersions = false
    @State private var showTableRead = false
    @State private var showPublish = false
    @State private var showKeys = false
    @State private var showNotes = false
    @State private var notesFocus: String?
    @StateObject private var notes = NotesStore()

    enum Mode: String, CaseIterable { case script, board }

    private var notesDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LR_NOTES_DEMO"] == "1"
        #else
        return false
        #endif
    }

    /// A shared play where I'm a commenter or a reader.
    private var readOnly: Bool { collab.map { !$0.link.canWrite } ?? false }

    init(play: Play, onOpenPlay: @escaping (UUID) -> Void, collab: CollabSession? = nil, recentChanges: [String: LineEdit] = [:]) {
        self.play = play
        self.onOpenPlay = onOpenPlay
        self.collab = collab
        self.recentChanges = recentChanges
        presence = collab?.presence ?? .none
    }

    /// The play itself and its toolbar. (Split from `body`, whose chain of sheets
    /// grew past what the type-checker will solve in one expression.)
    private var stage: some View {
        Group {
            switch mode {
            case .script:
                PlayEditorView(play: play, jumpTarget: $jumpTarget, noteCounts: notes.openCounts,
                               noteThreads: Dictionary(grouping: notes.threads.filter { !$0.resolved && !$0.detached }, by: \.root.elementID),
                               onShowNotes: { id in notesFocus = id.uuidString; showNotes = true },
                               others: presence.byElement,
                               onFocusChange: { presence.setFocus($0?.uuidString) },
                               // Readers and commenters see the script move; they don't type in it.
                               readOnly: readOnly,
                               notesEnabled: collab != nil && notes.canPost,
                               changed: recentChanges)
            case .board: BeatBoardView(play: play, onJump: { id in mode = .script; jumpTarget = id }, readOnly: readOnly)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Vue", selection: $mode) {
                    Text("Texte").tag(Mode.script)
                    Text("Tableau").tag(Mode.board)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup {
                // Notes belong to SHARED plays (everyone around the play, any account). The
                // earlier CloudKit notes-on-a-published-reading path is dormant, so a solo
                // play shows no Notes button rather than one that leads nowhere.
                if collab != nil || notesDemo {
                    Button { notesFocus = nil; showNotes = true } label: {
                        Label("Notes", systemImage: notes.unread > 0 ? "bubble.left.and.exclamationmark.bubble.right.fill" : "bubble.left.and.bubble.right")
                    }
                    .help(notes.unread > 0 ? Text("\(notes.unread) nouvelles notes") : Text("Notes"))
                }
                // The tools that CHANGE the script are for writers. A commenter's copy must
                // never drift from everyone else's (their edits are never sent).
                if collab != nil {
                    Button { showChanges = true } label: {
                        Label("Historique", systemImage: recentChanges.isEmpty ? "clock" : "clock.badge.exclamationmark")
                    }
                    .help(Text("\(recentChanges.count) lignes changées depuis ta dernière visite"))
                }
                if !readOnly {
                    Button { showAtelier = true } label: { Label("Atelier", systemImage: "sparkles") }
                    Button { showCast = true } label: { Label("Distribution", systemImage: "person.2") }
                }
                Button { showMeasures = true } label: { Label("Mesures", systemImage: "chart.bar") }
                Menu {
                    Button { showTableRead = true } label: { Label("Lecture à voix", systemImage: "speaker.wave.2") }
                    if collab != nil {
                        Button { showSharedVersions = true } label: { Label("Versions", systemImage: "clock.arrow.circlepath") }
                    } else if !readOnly {
                        Button { showVersions = true } label: { Label("Versions", systemImage: "clock.arrow.circlepath") }
                    }
                    Button { showPublish = true } label: {
                        Label(play.publicShareID == nil ? "Partager la lecture (web)" : "Lecture partagée — gérer",
                              systemImage: play.publicShareID == nil ? "globe" : "globe.badge.chevron.backward")
                    }
                    Divider()
                    // Lazy payloads — see PlayExport. Never render the play here.
                    ShareLink("Exporter — pour l'IA (.json)", item: PlayExport(play, kind: .aiJSON),
                              preview: SharePreview(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title))
                    ShareLink("Exporter — texte", item: PlayExport(play, kind: .text),
                              preview: SharePreview(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title))
                    if CollabBackend.isAvailable {
                        Divider()
                        Button { showCollab = true } label: {
                            Label(collab == nil ? "Écrire à plusieurs…" : "Inviter…", systemImage: "person.2.badge.plus")
                        }
                    }
                    Divider()
                    InterfaceLanguageRows(asSubmenu: true)
                    Divider()
                    Button { showKeys = true } label: { Label("Réglages…", systemImage: "gearshape") }
                } label: { Label("Plus", systemImage: "ellipsis.circle") }
            }
        }
    }

    var body: some View {
        stage
        .sheet(isPresented: $showCast) { CastPanel(play: play) }
        .sheet(isPresented: $showMeasures) { MeasuresView(play: play) }
        .sheet(isPresented: $showAtelier) { AtelierView(play: play, onOpenPlay: onOpenPlay) }
        .sheet(isPresented: $showVersions) { VersionsView(play: play) }
        .sheet(isPresented: $showTableRead) { TableReadView(play: play) }
        .sheet(isPresented: $showPublish, onDismiss: attachNotes) { PublishView(play: play) }
        .sheet(isPresented: $showNotes) {
            NotesPanel(play: play, notes: notes, focusElementID: notesFocus,
                       onJump: { id in mode = .script; jumpTarget = id },
                       onPublish: { showPublish = true })
        }
        .task(id: play.id) { attachNotes() }
        .onChange(of: play.elements?.count ?? 0) { _, _ in attachNotes() }
        .onChange(of: collab?.link.role ?? "") { _, _ in attachNotes() }
        .onDisappear { notes.detach() }
        .sheet(isPresented: $showKeys) { KeySetupView() }
        .sheet(isPresented: $showChanges) {
            if let collab {
                HistoryView(play: play, session: collab, onJump: { id in mode = .script; jumpTarget = id })
            }
        }
        .sheet(isPresented: $showSharedVersions) {
            if let collab { SharedVersionsView(play: play, session: collab) }
        }
        .sheet(isPresented: $showCollab) { CollabSheet(play: play, link: collab?.link, onShared: onOpenPlay) }
    }

    /// (Re)point the notes store at this play — after opening it, publishing or
    /// unpublishing it, or adding/removing blocks (which changes what "detached" means).
    private func attachNotes() {
        let ids = Set((play.elements ?? []).map { $0.id.uuidString })
        #if DEBUG
        if ProcessInfo.processInfo.environment["LR_NOTES_DEMO"] == "1" {
            let anchors = play.elementList.filter { $0.kind == .cue }.prefix(3).map { (id: $0.id.uuidString, text: $0.text ?? "") }
            let share = "demo-" + play.id.uuidString
            if notes.shareID != share { notes.attach(shareID: share, elementIDs: ids, backend: DemoComments(shareID: share, anchors: Array(anchors))) }
            else { notes.attach(shareID: share, elementIDs: ids) }
            return
        }
        #endif
        if let link = collab?.link {
            // A shared play: notes live beside the script, live, for writers and commenters.
            notes.attach(shareID: link.remoteID, elementIDs: ids,
                         backend: FirestoreComments(playID: link.remoteID, role: link.role, ownerUid: link.ownerUid),
                         shared: true, canPost: link.role == "writer" || link.role == "commenter")
            return
        }
        notes.attach(shareID: play.publicShareID, elementIDs: ids)
    }
}
