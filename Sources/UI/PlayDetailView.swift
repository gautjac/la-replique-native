import SwiftUI

/// Hosts a play: the Texte (editor) / Tableau (beat board) toggle, plus the
/// Distribution and Mesures inspectors as sheets.
struct PlayDetailView: View {
    @Bindable var play: Play
    @State private var mode: Mode = .script
    @State private var jumpTarget: UUID?
    @State private var showCast = false
    @State private var showMeasures = false

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
                Button { showCast = true } label: { Label("Distribution", systemImage: "person.2") }
                Button { showMeasures = true } label: { Label("Mesures", systemImage: "chart.bar") }
            }
        }
        .sheet(isPresented: $showCast) { CastPanel(play: play) }
        .sheet(isPresented: $showMeasures) { MeasuresView(play: play) }
    }
}
