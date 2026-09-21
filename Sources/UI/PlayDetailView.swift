import SwiftUI

/// Hosts a play: the Texte (editor) / Tableau (beat board) toggle, plus the
/// Distribution and Mesures inspectors as sheets.
struct PlayDetailView: View {
    @Bindable var play: Play
    var onOpenPlay: (UUID) -> Void
    /// Non-nil when this is a shared play, live.
    var collab: CollabSession?
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

    /// A shared play where I'm a commenter or a reader.
    private var readOnly: Bool { collab.map { !$0.link.canWrite } ?? false }

    init(play: Play, onOpenPlay: @escaping (UUID) -> Void, collab: CollabSession? = nil) {
        self.play = play
        self.onOpenPlay = onOpenPlay
        self.collab = collab
        presence = collab?.presence ?? .none
    }

    var body: some View {
        Group {
            switch mode {
            case .script:
                PlayEditorView(play: play, jumpTarget: $jumpTarget, noteCounts: notes.openCounts,
                               onShowNotes: { id in notesFocus = id.uuidString; showNotes = true },
                               others: presence.byElement,
                               onFocusChange: { presence.setFocus($0?.uuidString) },
                               // Readers and commenters see the script move; they don't type in it.
                               readOnly: readOnly)
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
                Button { notesFocus = nil; showNotes = true } label: {
                    Label("Notes", systemImage: notes.unread > 0 ? "bubble.left.and.exclamationmark.bubble.right.fill" : "bubble.left.and.bubble.right")
                }
                .help(notes.unread > 0 ? Text("\(notes.unread) nouvelles notes") : Text("Notes des lecteurs"))
                // The tools that CHANGE the script are for writers. A commenter's copy must
                // never drift from everyone else's (their edits are never sent).
                if !readOnly {
                    Button { showAtelier = true } label: { Label("Atelier", systemImage: "sparkles") }
                    Button { showCast = true } label: { Label("Distribution", systemImage: "person.2") }
                }
                Button { showMeasures = true } label: { Label("Mesures", systemImage: "chart.bar") }
                Menu {
                    Button { showTableRead = true } label: { Label("Lecture à voix", systemImage: "speaker.wave.2") }
                    if !readOnly { Button { showVersions = true } label: { Label("Versions", systemImage: "clock.arrow.circlepath") } }
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
        .onDisappear { notes.detach() }
        .sheet(isPresented: $showKeys) { KeySetupView() }
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
        notes.attach(shareID: play.publicShareID, elementIDs: ids)
    }
}
