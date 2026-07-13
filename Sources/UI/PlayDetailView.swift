import SwiftUI

/// Hosts a play: the Texte (editor) / Tableau (beat board) toggle, plus the
/// Distribution and Mesures inspectors as sheets.
struct PlayDetailView: View {
    @Bindable var play: Play
    var onOpenPlay: (UUID) -> Void
    @State private var mode: Mode = .script
    @State private var jumpTarget: UUID?
    @State private var showCast = false
    @State private var showMeasures = false
    @State private var showAtelier = false
    @State private var showVersions = false
    @State private var showTableRead = false

    enum Mode: String, CaseIterable { case script, board }

    var body: some View {
        Group {
            switch mode {
            case .script: PlayEditorView(play: play, jumpTarget: $jumpTarget)
            case .board: BeatBoardView(play: play, onJump: { id in mode = .script; jumpTarget = id })
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
                Button { showAtelier = true } label: { Label("Atelier", systemImage: "sparkles") }
                Button { showCast = true } label: { Label("Distribution", systemImage: "person.2") }
                Button { showMeasures = true } label: { Label("Mesures", systemImage: "chart.bar") }
                Menu {
                    Button { showTableRead = true } label: { Label("Lecture à voix", systemImage: "speaker.wave.2") }
                    Button { showVersions = true } label: { Label("Versions", systemImage: "clock.arrow.circlepath") }
                    Divider()
                    ShareLink("Exporter — pour l'IA (.json)", item: Exports.aiJSONString(play))
                    ShareLink("Exporter — texte", item: Exports.plainText(play))
                } label: { Label("Plus", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showCast) { CastPanel(play: play) }
        .sheet(isPresented: $showMeasures) { MeasuresView(play: play) }
        .sheet(isPresented: $showAtelier) { AtelierView(play: play, onOpenPlay: onOpenPlay) }
        .sheet(isPresented: $showVersions) { VersionsView(play: play) }
        .sheet(isPresented: $showTableRead) { TableReadView(play: play) }
    }
}
