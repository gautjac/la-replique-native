import SwiftUI
import SwiftData

/// Beat colours + labels (mirrors the web beats vocabulary).
enum BeatMeta {
    static let all: [Beat] = [.setup, .inciting, .rising, .turn, .crisis, .climax, .resolution]
    static func label(_ b: Beat, _ lang: Lang) -> String {
        switch b {
        case .setup: return lang == .fr ? "Exposition" : "Setup"
        case .inciting: return lang == .fr ? "Élément déclencheur" : "Inciting"
        case .rising: return lang == .fr ? "Montée" : "Rising"
        case .turn: return lang == .fr ? "Pivot" : "Turn"
        case .crisis: return lang == .fr ? "Crise" : "Crisis"
        case .climax: return lang == .fr ? "Point culminant" : "Climax"
        case .resolution: return lang == .fr ? "Dénouement" : "Resolution"
        }
    }
    static func color(_ b: Beat) -> Color {
        switch b {
        case .setup: return Color(hex: 0x64748b)
        case .inciting: return Color(hex: 0x0ea5b7)
        case .rising: return Theme.gel
        case .turn: return Theme.plum
        case .crisis: return Theme.amber
        case .climax: return Theme.rose
        case .resolution: return Theme.jade
        }
    }
}

struct BeatBoardView: View {
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    var onJump: (UUID) -> Void

    private var decomposed: (preamble: [Element], blocks: [Editing.Block]) { Editing.decompose(play) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Glisse les cartes… (déplace avec ↑ ↓) — chaque carte est une scène.")
                    .font(.caption).foregroundStyle(Theme.inkFaint)
                let blocks = decomposed.blocks
                if blocks.isEmpty {
                    emptyState
                } else {
                    ForEach(blocks) { block in
                        if block.isAct {
                            ActRow(play: play, act: block.heading,
                                   onAddScene: { Editing.addSceneAfter(play, blockID: block.id, context: context) },
                                   onMove: { Editing.moveBlock(play, blockID: block.id, dir: $0) })
                        } else {
                            SceneCard(play: play, block: block,
                                      onJump: { onJump(block.heading.id) },
                                      onMove: { Editing.moveBlock(play, blockID: block.id, dir: $0) })
                        }
                    }
                }
                HStack {
                    Button { Editing.addSceneAfter(play, blockID: decomposed.blocks.last?.id, context: context) } label: {
                        Label("Ajouter une scène", systemImage: "plus")
                    }.buttonStyle(.borderedProminent)
                    Button { Editing.addActAtEnd(play, context: context) } label: {
                        Label("Ajouter un acte", systemImage: "plus")
                    }.buttonStyle(.bordered)
                }.padding(.top, 6)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(Theme.desk)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Aucune scène. Ajoute-en une pour bâtir ta structure.").foregroundStyle(Theme.inkFaint)
            Button("Scène") { Editing.addSceneAfter(play, blockID: nil, context: context) }
                .buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

private struct MoveButtons: View {
    var onMove: (Int) -> Void
    var body: some View {
        HStack(spacing: 2) {
            Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
            Button { onMove(1) } label: { Image(systemName: "chevron.down") }
        }
        .buttonStyle(.borderless).foregroundStyle(Theme.inkFaint).font(.caption)
    }
}

private struct ActRow: View {
    @Bindable var play: Play
    @Bindable var act: Element
    var onAddScene: () -> Void
    var onMove: (Int) -> Void
    var body: some View {
        HStack {
            TextField("ACTE", text: label).textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold)).kerning(2).foregroundStyle(.white)
            Spacer()
            Button("+ Scène", action: onAddScene).buttonStyle(.borderless).font(.caption).foregroundStyle(Theme.gelBright)
            MoveButtons(onMove: onMove)
        }
        .padding(12)
        .background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
    }
    private var label: Binding<String> {
        Binding(get: { act.label ?? "" }, set: { act.label = $0.uppercased(); play.touch() })
    }
}

private struct SceneCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    let block: Editing.Block
    var onJump: () -> Void
    var onMove: (Int) -> Void

    private var scene: Element { block.heading }
    private var stats: Stats.ElementStats { Stats.elementStats(block.els) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("SCÈNE", text: label).textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .bold)).kerning(1.5).foregroundStyle(.white)
                    TextField("Lieu, moment…", text: setting).textFieldStyle(.plain)
                        .font(.caption).foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button(action: onJump) { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).foregroundStyle(Theme.gelBright)
                MoveButtons(onMove: onMove)
            }
            TextField("Ce qui se passe, ce que ça change…", text: synopsis, axis: .vertical)
                .textFieldStyle(.plain).font(.callout).foregroundStyle(.white)
                .padding(8).background(Theme.desk, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                beatMenu
                Spacer()
                HStack(spacing: 4) {
                    ForEach(stats.speakerIDs, id: \.self) { id in
                        Circle().fill(Color(hexString: play.character(id: id)?.colorHex)).frame(width: 8, height: 8)
                    }
                }
                Text("\(stats.lines) répliques").font(.caption2).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(14)
        .background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            if let b = scene.beat {
                RoundedRectangle(cornerRadius: 2).fill(BeatMeta.color(b)).frame(width: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.rule))
    }

    private var beatMenu: some View {
        Menu {
            Button("— fonction —") { scene.beat = nil; play.touch() }
            ForEach(BeatMeta.all, id: \.self) { b in
                Button(BeatMeta.label(b, play.lang)) { scene.beat = b; play.touch() }
            }
        } label: {
            Text(scene.beat.map { BeatMeta.label($0, play.lang) } ?? "— fonction —")
                .font(.caption.weight(.semibold))
                .foregroundStyle(scene.beat.map(BeatMeta.color) ?? Theme.inkFaint)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var label: Binding<String> {
        Binding(get: { scene.label ?? "" }, set: { scene.label = $0.uppercased(); play.touch() })
    }
    private var setting: Binding<String> {
        Binding(get: { scene.setting ?? "" }, set: { scene.setting = $0; play.touch() })
    }
    private var synopsis: Binding<String> {
        Binding(get: { scene.synopsis ?? "" }, set: { scene.synopsis = $0.isEmpty ? nil : $0; play.touch() })
    }
}
