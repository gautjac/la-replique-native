import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

// MARK: - Board

/// A corkboard of scene index cards, laid out in columns by act. Drag a card to
/// reorder it or move it to another act; tap it to open the detail sheet.
struct BeatBoardView: View {
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    var onJump: (UUID) -> Void

    @State private var detailSceneID: UUID?

    private struct Column: Identifiable {
        let id: UUID          // act id, or a stable sentinel for the actless first column
        let act: Element?
        let scenes: [Editing.Block]
        let nextHeadID: UUID? // block to insert-before when appending to this column
        var label: String
    }

    private static let looseColumnID = UUID()

    private func columns() -> [Column] {
        let blocks = Editing.decompose(play).blocks
        // Group into (act?, [sceneBlocks]) — a plain in-place fold (no captured
        // mutable state, which Swift 6 strict concurrency flags as a data race).
        var groups: [(act: Element?, scenes: [Editing.Block])] = []
        for b in blocks {
            if b.isAct {
                groups.append((b.heading, []))
            } else if groups.isEmpty {
                groups.append((nil, [b])) // scenes before any act → a "Début" column
            } else {
                groups[groups.count - 1].scenes.append(b)
            }
        }
        // Attach the "next column head" for append-to-end drops.
        return groups.enumerated().map { i, g in
            let next = i + 1 < groups.count ? groups[i + 1] : nil
            let nextHead = next.flatMap { $0.act?.id ?? $0.scenes.first?.heading.id }
            let label = g.act?.label?.isEmpty == false ? g.act!.label! : (g.act != nil ? "ACTE" : "Début")
            return Column(id: g.act?.id ?? Self.looseColumnID, act: g.act, scenes: g.scenes, nextHeadID: nextHead, label: label)
        }
    }

    var body: some View {
        let cols = columns()
        VStack(spacing: 0) {
            HStack {
                Text("Glisse une carte pour la déplacer • touche-la pour les détails.")
                    .font(.caption).foregroundStyle(Theme.inkFaint)
                Spacer()
                Button { _ = Editing.addActAtEnd(play, context: context) } label: {
                    Label("Acte", systemImage: "plus.rectangle.on.rectangle")
                }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if cols.isEmpty {
                emptyState
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(cols) { col in
                            columnView(col, allColumns: cols)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Theme.desk)
        .sheet(item: Binding(get: { detailSceneID.map { IdemID(id: $0) } }, set: { detailSceneID = $0?.id })) { wrap in
            if let block = Editing.decompose(play).blocks.first(where: { $0.id == wrap.id && !$0.isAct }) {
                SceneDetailSheet(
                    play: play,
                    block: block,
                    acts: cols.map { ($0.act?.id, $0.label) },
                    currentActID: currentActID(of: block.id, in: cols),
                    onJump: { onJump(block.heading.id); detailSceneID = nil },
                    onMoveToAct: { moveScene(block.id, toActID: $0, in: cols) },
                    onRemove: { Editing.removeSceneHeading(play, sceneID: block.id, context: context); detailSceneID = nil }
                )
            }
        }
    }

    // MARK: Column

    @ViewBuilder
    private func columnView(_ col: Column, allColumns: [Column]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ColumnHeader(play: play, act: col.act, title: col.label,
                         onAddScene: { _ = Editing.addSceneAfter(play, blockID: col.scenes.last?.id ?? col.act?.id, context: context) })

            ForEach(col.scenes) { block in
                SceneCardView(
                    play: play,
                    block: block,
                    onOpen: { detailSceneID = block.heading.id },
                    onDropBefore: { dragged in Editing.moveBlock(play, blockID: dragged, before: block.id) },
                    onMove: { Editing.moveBlock(play, blockID: block.id, dir: $0) },
                    onJump: { onJump(block.heading.id) }
                )
            }

            // Trailing drop zone — dropping here appends to this column.
            ColumnDropZone(empty: col.scenes.isEmpty) { dragged in
                Editing.moveBlock(play, blockID: dragged, before: col.nextHeadID)
            }
        }
        .frame(width: 300, alignment: .top)
    }

    private func currentActID(of sceneID: UUID, in cols: [Column]) -> UUID? {
        cols.first { $0.scenes.contains { $0.id == sceneID } }?.act?.id
    }

    private func moveScene(_ sceneID: UUID, toActID actID: UUID?, in cols: [Column]) {
        guard let target = cols.first(where: { $0.act?.id == actID }) else { return }
        Editing.moveBlock(play, blockID: sceneID, before: target.nextHeadID)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group").font(.system(size: 40)).foregroundStyle(Theme.inkFaint)
            Text("Aucune scène. Ajoute une carte pour bâtir ta structure.").foregroundStyle(Theme.inkFaint)
            Button { _ = Editing.addSceneAfter(play, blockID: nil, context: context) } label: {
                Label("Première scène", systemImage: "plus")
            }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sheet needs an Identifiable wrapper around the scene UUID.
private struct IdemID: Identifiable { let id: UUID }

// MARK: - Column header

private struct ColumnHeader: View {
    @Bindable var play: Play
    let act: Element?
    let title: String
    var onAddScene: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let act {
                TextField("ACTE", text: Binding(
                    get: { act.label ?? "" },
                    set: { act.label = $0.uppercased(); play.touch() }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .heavy)).kerning(2).foregroundStyle(.white)
            } else {
                Text(title).font(.system(size: 14, weight: .heavy)).kerning(2).foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button(action: onAddScene) { Image(systemName: "plus") }
                .buttonStyle(.borderless).foregroundStyle(Theme.gelBright).font(.callout)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}

// MARK: - Scene card

private struct SceneCardView: View {
    @Bindable var play: Play
    let block: Editing.Block
    var onOpen: () -> Void
    var onDropBefore: (UUID) -> Void
    var onMove: (Int) -> Void
    var onJump: () -> Void

    @State private var targeted = false
    private var scene: Element { block.heading }
    private var stats: Stats.ElementStats { Stats.elementStats(block.els) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scene.label?.isEmpty == false ? scene.label! : "SCÈNE")
                .font(.system(size: 14, weight: .bold)).kerning(1).foregroundStyle(.white)
                .lineLimit(1)
            if let s = scene.setting, !s.isEmpty {
                Text(s).font(.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            if let syn = scene.synopsis, !syn.isEmpty {
                Text(syn).font(.callout).foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ajoute un synopsis…").font(.callout).foregroundStyle(Theme.inkFaint.opacity(0.6)).italic()
            }
            HStack(spacing: 8) {
                if let b = scene.beat {
                    Text(BeatMeta.label(b, play.lang))
                        .font(.caption2.weight(.semibold)).foregroundStyle(BeatMeta.color(b))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(BeatMeta.color(b).opacity(0.16), in: Capsule())
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(stats.speakerIDs.prefix(6), id: \.self) { id in
                        Circle().fill(Color(hexString: play.character(id: id)?.colorHex)).frame(width: 7, height: 7)
                    }
                }
                Text("\(stats.lines)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.inkFaint)
                Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if let b = scene.beat {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                    .fill(BeatMeta.color(b)).frame(width: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? Theme.gelBright : Theme.rule, lineWidth: targeted ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .draggable(scene.id.uuidString) {
            // Drag preview: a lifted mini card.
            Text(scene.label?.isEmpty == false ? scene.label! : "SCÈNE")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(10).background(Theme.deskLight, in: RoundedRectangle(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            onDropBefore(id); return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button { onOpen() } label: { Label("Détails", systemImage: "square.text.square") }
            Button { onJump() } label: { Label("Ouvrir dans le texte", systemImage: "arrow.up.forward.square") }
            Divider()
            Button { onMove(-1) } label: { Label("Monter", systemImage: "chevron.up") }
            Button { onMove(1) } label: { Label("Descendre", systemImage: "chevron.down") }
        }
    }
}

// MARK: - Column drop zone (append)

private struct ColumnDropZone: View {
    let empty: Bool
    var onDrop: (UUID) -> Void
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(targeted ? Theme.gelBright : Theme.rule.opacity(empty ? 1 : 0.5))
            .frame(height: empty ? 90 : 44)
            .overlay {
                Text(empty ? "Dépose une scène ici" : "＋")
                    .font(.caption).foregroundStyle(targeted ? Theme.gelBright : Theme.inkFaint.opacity(0.7))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let s = items.first, let id = UUID(uuidString: s) else { return false }
                onDrop(id); return true
            } isTargeted: { targeted = $0 }
    }
}

// MARK: - Detail sheet

private struct SceneDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var play: Play
    let block: Editing.Block
    let acts: [(id: UUID?, label: String)]
    let currentActID: UUID?
    var onJump: () -> Void
    var onMoveToAct: (UUID?) -> Void
    var onRemove: () -> Void

    private var scene: Element { block.heading }
    private var stats: Stats.ElementStats { Stats.elementStats(block.els) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scène") {
                    TextField("Titre (ex. SCÈNE 1)", text: bind(\.label, upper: true))
                    TextField("Lieu, moment…", text: bind(\.setting))
                }
                Section("Ce qui se passe, ce que ça change") {
                    TextField("Synopsis / intention", text: bind(\.synopsis), axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Fonction dramatique") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                        beatChip(nil)
                        ForEach(BeatMeta.all, id: \.self) { beatChip($0) }
                    }
                    .padding(.vertical, 4)
                }
                if acts.count > 1 {
                    Section("Acte") {
                        Picker("Acte", selection: Binding(get: { currentActID }, set: { onMoveToAct($0) })) {
                            ForEach(acts, id: \.id) { a in Text(a.label).tag(a.id) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section {
                    Button { onJump() } label: { Label("Ouvrir dans le texte", systemImage: "arrow.up.forward.square") }
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Retirer l'en-tête (garde les répliques)", systemImage: "scissors")
                    }
                } footer: {
                    Text("\(stats.lines) répliques · \(stats.speakerIDs.count) personnages présents")
                }
            }
            .navigationTitle(scene.label?.isEmpty == false ? scene.label! : "Scène")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
    }

    @ViewBuilder
    private func beatChip(_ b: Beat?) -> some View {
        let selected = scene.beat == b
        let color = b.map(BeatMeta.color) ?? Theme.inkFaint
        Button {
            scene.beat = b; play.touch()
        } label: {
            Text(b.map { BeatMeta.label($0, play.lang) } ?? "— aucune —")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? .white : color)
                .background(selected ? color : color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func bind(_ key: ReferenceWritableKeyPath<Element, String?>, upper: Bool = false) -> Binding<String> {
        Binding(
            get: { scene[keyPath: key] ?? "" },
            set: { scene[keyPath: key] = ($0.isEmpty ? nil : (upper ? $0.uppercased() : $0)); play.touch() }
        )
    }
}
