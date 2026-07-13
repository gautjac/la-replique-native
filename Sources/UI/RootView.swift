import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Play.updatedAt, order: .reverse) private var plays: [Play]

    @State private var selectedID: UUID?
    @State private var importing = false
    @State private var showKeys = false

    var selectedPlay: Play? { plays.first { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(plays) { play in
                    PlayRow(play: play).tag(play.id)
                        .contextMenu {
                            Button(role: .destructive) { delete(play) } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Mes pièces")
            .toolbar {
                ToolbarItemGroup {
                    Button { newPlay() } label: { Label("Nouvelle pièce", systemImage: "plus") }
                    Button { importing = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                    Button { showKeys = true } label: { Label("Clés", systemImage: "key") }
                }
            }
            #if os(macOS)
            .frame(minWidth: 260)
            #endif
        } detail: {
            if let play = selectedPlay {
                PlayDetailView(play: play)
            } else {
                EmptyStateView()
            }
        }
        .task { seedIfEmpty() }
        .sheet(isPresented: $showKeys) { KeySetupView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // MARK: Actions

    private func newPlay() {
        let p = Play(title: "Pièce sans titre", lang: .fr)
        context.insert(p)
        selectedID = p.id
    }

    private func delete(_ play: Play) {
        if selectedID == play.id { selectedID = nil }
        context.delete(play)
    }

    private func seedIfEmpty() {
        guard plays.isEmpty,
              let url = Bundle.main.url(forResource: "sample-play", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let doc = try? PlayFormat.decode(data) else { return }
        let p = PlayFormat.makePlay(from: doc, into: context)
        selectedID = p.id
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let doc = try? PlayFormat.decode(data) else { return }
        let p = PlayFormat.makePlay(from: doc, into: context)
        selectedID = p.id
    }
}

private struct PlayRow: View {
    let play: Play
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(play.lang.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.gel.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.gelBright)
                Text(play.title.isEmpty ? "Pièce sans titre" : play.title)
                    .font(.headline).lineLimit(1)
            }
            if !play.subtitle.isEmpty {
                Text(play.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("\(play.elementList.filter { $0.kind == .cue }.count) répliques · \(play.characterList.count) personnages")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote").font(.system(size: 44)).foregroundStyle(Theme.gel)
            Text("Choisis une pièce, ou crée-en une.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.desk)
    }
}
