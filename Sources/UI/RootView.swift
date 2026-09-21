import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Play.updatedAt, order: .reverse) private var plays: [Play]
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var inbox = NotesInbox.shared
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var selectedID: UUID?
    @State private var infoPlay: Play?
    @State private var importing = false
    @State private var showKeys = false
    @State private var showOnboarding = false
    @State private var joining = false
    @State private var wantsKeysAfterOnboarding = false

    var selectedPlay: Play? { plays.first { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(plays) { play in
                    PlayRow(play: play, unreadNotes: play.publicShareID.flatMap { inbox.unread[$0] } ?? 0).tag(play.id)
                        // Double-click opens the play's info card without stealing
                        // the List's single-click selection.
                        .simultaneousGesture(TapGesture(count: 2).onEnded { infoPlay = play })
                        .contextMenu {
                            Button { infoPlay = play } label: {
                                Label("Informations…", systemImage: "info.circle")
                            }
                            Divider()
                            Button(role: .destructive) { delete(play) } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                }
                // Shared plays come from their own local store (never iCloud-mirrored).
                if CollabBackend.isAvailable {
                    SharedPlaysList(onRemove: { p in
                        if selectedID == p.id { selectedID = nil }
                        CollabStore.remove(p.id)
                    })
                    .modelContainer(CollabStore.container)
                }
            }
            .navigationTitle("Mes pièces")
            .toolbar {
                ToolbarItemGroup {
                    Button { newPlay() } label: { Label("Nouvelle pièce", systemImage: "plus") }
                    Button { importing = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                    if CollabBackend.isAvailable {
                        Button { joining = true } label: { Label("Rejoindre une pièce", systemImage: "person.2.badge.plus") }
                    }
                    InterfaceLanguageMenu()
                    // Settings live in the Settings window (⌘,) on macOS and the
                    // ••• menu on both platforms; this button is the iOS way in.
                    #if os(iOS)
                    Button { showKeys = true } label: { Label("Réglages", systemImage: "gearshape") }
                    #endif
                }
            }
            #if os(macOS)
            .frame(minWidth: 260)
            #endif
        } detail: {
            if let play = selectedPlay {
                PlayDetailView(play: play, onOpenPlay: { selectedID = $0 })
            } else if let id = selectedID, CollabBackend.isAvailable {
                SharedPlayDetail(playID: id, onOpenPlay: { selectedID = $0 })   // falls back to the empty state
            } else {
                EmptyStateView()
            }
        }
        // Re-render the whole tree when the interface language switches, WITHOUT
        // losing this view's state (selection, open sheets) — the id sits on the
        // split view, not on RootView itself.
        .id(loc.language)
        .task {
            #if DEBUG
            Persistence.primeSchemaIfRequested(context)
            if let bench = Bench.seedIfRequested(context) { selectedID = bench.id; return }
            #endif
            await seedIfEmpty()
            #if DEBUG
            await CollabDebug.runLaunchHooks(context) { selectedID = $0 }
            #endif
        }
        .task {
            if !hasOnboarded { showOnboarding = true }
        }
        // New readers' notes → a badge in the library. One light pass when the app
        // comes forward; never while typing.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await inbox.refresh(shareIDs: plays.compactMap(\.publicShareID))
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            hasOnboarded = true
            if wantsKeysAfterOnboarding { wantsKeysAfterOnboarding = false; showKeys = true }
        }) {
            OnboardingView(onAddKey: { wantsKeysAfterOnboarding = true })
        }
        .onChange(of: router.openPlayID) { _, id in
            // An App Intent (Siri / Shortcuts) asked to open a play.
            guard let id else { return }
            selectedID = id
            router.openPlayID = nil
        }
        .sheet(isPresented: $showKeys) { KeySetupView() }
        .sheet(isPresented: $joining) { JoinSheet(onJoined: { selectedID = $0 }) }
        .sheet(item: $infoPlay) { PlayInfoSheet(play: $0) }
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

    /// Seeds the bundled sample ("La porte") only when the library is *really*
    /// empty. On a CloudKit store a fresh device reads empty for a beat while the
    /// first import is still in flight — seeding then gave every device its own
    /// duplicate of the sample (2 copies of "La porte" on iPhone + iPad). So on a
    /// synced store: let the import land first, then re-check against the store
    /// itself rather than the `@Query`, whose snapshot is captured and can be stale.
    private func seedIfEmpty() async {
        if Persistence.tier == .cloudKit {
            try? await Task.sleep(for: .seconds(8))
        }
        let empty = ((try? context.fetchCount(FetchDescriptor<Play>())) ?? 1) == 0
        guard empty,
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

struct PlayRow: View {
    let play: Play
    var unreadNotes = 0
    var shared = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(play.lang.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.gel.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.gelBright)
                Text(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title)
                    .font(.headline).lineLimit(1)
                if shared { Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(Theme.gelBright) }
                if unreadNotes > 0 { Spacer(minLength: 4); NoteBadge(count: unreadNotes) }
            }
            if !play.subtitle.isEmpty {
                Text(play.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("\(play.cueCount) répliques · \(play.characterCount) personnages")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote").font(.system(size: 44)).foregroundStyle(Theme.gel)
            Text("Choisis une pièce, ou crée-en une.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.desk)
    }
}
