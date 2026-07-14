import SwiftUI

/// P0: a read-only rendering of a play — the lit prompt-book page. The editable
/// editor lands in P1; this proves the data model, CloudKit store, import and the
/// design identity on real material.
struct ScriptReadView: View {
    let play: Play

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                page
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(Theme.desk)
        .navigationTitle(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            if !play.subtitle.isEmpty {
                Text(play.subtitle).font(.title3).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.bottom, 18)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(play.elementList) { el in
                row(el)
            }
            if play.elementList.isEmpty {
                Text("La page est vide.").foregroundStyle(Theme.inkFaint).padding(.vertical, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func row(_ el: Element) -> some View {
        switch el.kind {
        case .act:
            HStack {
                Rectangle().fill(Theme.paperShade).frame(height: 1)
                Text(el.label ?? "").font(.system(size: 16, weight: .bold)).kerning(3)
                    .foregroundStyle(Theme.ink).fixedSize()
                Rectangle().fill(Theme.paperShade).frame(height: 1)
            }
            .padding(.vertical, 18)

        case .scene:
            VStack(alignment: .leading, spacing: 3) {
                Text(el.label ?? "").font(.system(size: 15, weight: .bold)).kerning(2).foregroundStyle(Theme.ink)
                if let s = el.setting, !s.isEmpty {
                    Text(s).font(.subheadline).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.top, 16).padding(.bottom, 8)

        case .stage:
            Text(el.text ?? "")
                .font(.system(size: 16)).foregroundStyle(Theme.inkSoft)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.gel.opacity(0.55)).frame(width: 2)
                }
                .padding(.vertical, 8)

        case .action:
            Text(el.text ?? "").font(.system(size: 16)).foregroundStyle(Theme.ink).padding(.vertical, 6)

        case .cue:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text((play.character(id: el.characterID)?.name ?? "?").uppercased())
                        .font(.system(size: 15, weight: .bold)).kerning(2)
                        .foregroundStyle(Color(hexString: play.character(id: el.characterID)?.colorHex))
                    if let p = el.parenthetical, !p.isEmpty {
                        Text(p).font(.subheadline).foregroundStyle(Theme.inkFaint)
                    }
                }
                Text(el.text ?? "").font(.system(size: 18)).foregroundStyle(Theme.ink)
                if let alt = el.alt, !alt.isEmpty {
                    Text(alt).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.cyan).frame(width: 2) }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
