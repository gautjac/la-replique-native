import SwiftUI

struct MeasuresView: View {
    @Environment(\.dismiss) private var dismiss
    let play: Play

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statCards
                    presenceGrid
                    throughLine
                    doubling
                }
                .padding(20)
            }
            .background(Theme.deskLight)
            .navigationTitle("Mesures")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    private var totals: Stats.PlayTotals { Stats.castStats(play).totals }

    private var statCards: some View {
        let t = totals
        return LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            card("Répliques", "\(t.totalLines)")
            card("Mots dits", "\(t.spokenWords)")
            card("Scènes", "\(t.sceneCount)")
            card("Actes", "\(t.actCount)")
            card("Durée estimée", Stats.formatRuntime(t.runtimeMinutes, play.lang), wide: true, accent: true)
        }
    }

    private func card(_ label: String, _ value: String, wide: Bool = false, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.weight(.bold)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent ? Theme.gel.opacity(0.16) : Theme.deskLight, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent ? Theme.gel.opacity(0.4) : Theme.rule))
        .gridCellColumns(wide ? 2 : 1)
    }

    @ViewBuilder private var presenceGrid: some View {
        let scenes = Stats.scenes(play)
        VStack(alignment: .leading, spacing: 8) {
            Text("GRILLE DE PRÉSENCE").font(.caption2.weight(.bold)).kerning(1.2).foregroundStyle(Theme.inkFaint)
            Text("Qui parle dans quelle scène.").font(.caption).foregroundStyle(.secondary)
            if scenes.isEmpty {
                Text("Ajoute des scènes pour voir la grille.").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .center, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Color.clear.frame(width: 96, height: 1)
                            ForEach(Array(scenes.enumerated()), id: \.offset) { i, _ in
                                Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(play.characterList) { c in
                            GridRow {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hexString: c.colorHex)).frame(width: 8, height: 8)
                                    Text(c.name).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                }.frame(width: 96, alignment: .leading)
                                ForEach(Array(scenes.enumerated()), id: \.offset) { _, seg in
                                    Circle()
                                        .fill(seg.speakerIDs.contains(c.id.uuidString) ? Color(hexString: c.colorHex) : Theme.rule)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var throughLine: some View {
        let (labels, lines) = Stats.throughLines(play)
        if !labels.isEmpty && !play.characterList.isEmpty {
            let globalMax = max(1, lines.map(\.maxCount).max() ?? 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("FIL DE CHAQUE PERSONNAGE").font(.caption2.weight(.bold)).kerning(1.2).foregroundStyle(Theme.inkFaint)
                ForEach(lines, id: \.character.id) { tl in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hexString: tl.character.colorHex)).frame(width: 8, height: 8)
                            Text(tl.character.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(tl.perScene.enumerated()), id: \.offset) { _, n in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(n > 0 ? Color(hexString: tl.character.colorHex) : Theme.rule)
                                    .frame(height: CGFloat(max(Double(n) / Double(globalMax) * 30, n > 0 ? 6 : 3)))
                                    .frame(maxWidth: .infinity)
                            }
                        }.frame(height: 30)
                    }
                }
            }
        }
    }

    @ViewBuilder private var doubling: some View {
        let groups = Stats.doubling(play)
        if play.characterList.count >= 2, !groups.isEmpty {
            let doublings = groups.filter { $0.count > 1 }
            VStack(alignment: .leading, spacing: 8) {
                Text("DOUBLURES POSSIBLES").font(.caption2.weight(.bold)).kerning(1.2).foregroundStyle(Theme.inkFaint)
                Text("Rôles qui ne partagent jamais une scène.").font(.caption).foregroundStyle(.secondary)
                if doublings.isEmpty {
                    Text("Chaque rôle partage une scène avec un autre.").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        HStack(spacing: 8) {
                            Text("Comédien·ne \(i + 1)").font(.caption).foregroundStyle(.secondary)
                            ForEach(g, id: \.self) { id in
                                if let c = play.character(id: id) {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color(hexString: c.colorHex)).frame(width: 8, height: 8)
                                        Text(c.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    Text("\(groups.count) comédien·ne·s · \(play.characterList.count) rôles")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
