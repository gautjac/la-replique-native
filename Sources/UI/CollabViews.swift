import SwiftUI
import SwiftData

// Writing together — the interface. The editor itself is untouched: a shared
// play opens in the same PlayDetailView, fed from the shared-plays store, with a
// CollabSession running beside it.

/// The « À plusieurs » section of the library. Lives in the shared-plays store,
/// so the caller injects that container: `.modelContainer(CollabStore.container)`.
struct SharedPlaysList: View {
    @Query(sort: \Play.updatedAt, order: .reverse) private var plays: [Play]
    var onRemove: (Play) -> Void

    var body: some View {
        if !plays.isEmpty {
            Section("À plusieurs") {
                ForEach(plays) { play in
                    PlayRow(play: play, shared: true).tag(LibraryItem.shared(play.id))
                        .contextMenu {
                            Button(role: .destructive) { onRemove(play) } label: {
                                Label("Retirer de cet appareil", systemImage: "minus.circle")
                            }
                        }
                }
            }
        }
    }
}

/// Opens a shared play: same detail view, shared-plays store, live session.
struct SharedPlayDetail: View {
    let playID: UUID
    var onOpenPlay: (UUID) -> Void

    var body: some View {
        if let play = CollabStore.play(playID), let link = CollabStore.link(playID) {
            SharedPlayHost(play: play, link: link, onOpenPlay: onOpenPlay)
                .id(playID)
                .modelContainer(CollabStore.container)
        } else {
            EmptyStateView()
        }
    }
}

private struct SharedPlayHost: View {
    let play: Play
    let link: CollabLink
    var onOpenPlay: (UUID) -> Void
    @StateObject private var session: CollabSession

    init(play: Play, link: CollabLink, onOpenPlay: @escaping (UUID) -> Void) {
        self.play = play; self.link = link; self.onOpenPlay = onOpenPlay
        _session = StateObject(wrappedValue: CollabSession(play: play, link: link))
    }

    var body: some View {
        PlayDetailView(play: play, onOpenPlay: onOpenPlay, collab: session)
            .safeAreaInset(edge: .bottom, spacing: 0) { CollabStatusBar(session: session) }
            .onAppear { session.start() }
            .onDisappear { session.stop() }
    }
}

/// One quiet line under the script: are we live, and may I write?
struct CollabStatusBar: View {
    @ObservedObject var session: CollabSession
    @ObservedObject private var presence: PresenceChannel

    init(session: CollabSession) { self.session = session; presence = session.presence }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.inkFaint)
            if !session.link.canWrite {
                Text("· lecture seule").font(.caption).foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            // Who else has the play open, in their colours.
            HStack(spacing: -5) {
                ForEach(presence.others.prefix(5)) { who in
                    Text(String(who.name.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color(hexString: who.colorHex), in: Circle())
                        .overlay(Circle().stroke(Theme.deskLight, lineWidth: 1.5))
                        .help(who.name)
                }
            }
            if !presence.others.isEmpty {
                Text(presence.others.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Theme.deskLight)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private var color: Color {
        switch session.status { case .live: return Theme.jade; case .connecting: return Theme.gel; case .offline: return Theme.amber; case .gone: return Theme.rose }
    }
    private var label: LocalizedStringKey {
        switch session.status {
        case .live: return "À plusieurs · en direct"
        case .connecting: return "À plusieurs · connexion…"
        case .offline: return "Hors ligne — tes changements partiront au retour du réseau"
        case .gone: return "Cette pièce n'est plus partagée avec toi"
        }
    }
}

// MARK: - Share / invite

/// From a play's ••• menu. A solo play: explain, then share it. A shared play:
/// make an invitation at a chosen role.
struct CollabSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    let link: CollabLink?
    var onShared: (UUID) -> Void

    @AppStorage("notes.authorName") private var name = ""
    @ObservedObject private var auth = CollabAuth.shared
    @State private var role = "writer"
    @State private var invite: CollabService.Invite?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !auth.isSignedIn {
                        CollabSignInView()
                    } else if let link {
                        inviteSection(link)
                        MembersSection(link: link, onLeft: { dismiss() })
                    } else {
                        shareSection
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(Theme.rose)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Écrire à plusieurs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 600)
        #endif
        .onAppear { if name.isEmpty { name = auth.person?.name ?? play.author } }
        .onChange(of: auth.person?.name ?? "") { _, n in if name.isEmpty { name = n } }
    }

    @ViewBuilder private var shareSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Une pièce, plusieurs mains", systemImage: "person.2").font(.headline).foregroundStyle(.white)
            Text("Les personnes que tu invites voient le texte changer en direct — sur iPhone, iPad, Mac, et bientôt dans un navigateur. Chacun garde sa copie hors ligne ; tout se réconcilie au retour du réseau.")
                .foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Text("Une pièce partagée quitte ton iCloud privé : elle est conservée sur le serveur de La Réplique, accessible aux seules personnes invitées.")
                .font(.footnote).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            FieldGroup("Ton nom, pour les autres") { TextField("Ton nom", text: $name).sheetField() }
            Button {
                run { let id = try await CollabService.share(play, from: context, as: signedName); dismiss(); onShared(id) }
            } label: { Label("Partager cette pièce", systemImage: "person.2.badge.plus").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || signedName.isEmpty)
            .overlay { if busy { ProgressView().controlSize(.small) } }
        }
    }

    @ViewBuilder private func inviteSection(_ link: CollabLink) -> some View {
        if link.ownerUid == CollabBackend.uid {
            FieldGroup("Inviter quelqu'un") {
                Picker("", selection: $role) {
                    Text("Écrire").tag("writer")
                    Text("Commenter").tag("commenter")
                    Text("Lire").tag("reader")
                }
                .labelsHidden().pickerStyle(.segmented)
                Button {
                    run { invite = try await CollabService.invite(to: link, role: role) }
                } label: { Label("Créer une invitation", systemImage: "envelope.badge").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(busy)
            }
            if let invite {
                FieldGroup("Code d'invitation — valable 14 jours") {
                    Text(invite.token)
                        .font(.system(size: 28, weight: .bold, design: .monospaced)).kerning(3)
                        .foregroundStyle(Theme.gelBright).textSelection(.enabled)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.desk, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
                    HStack(spacing: 8) {
                        Button { copy(invite.token) } label: {
                            Label(copied ? "Copié" : "Copier le code", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                        }
                        ShareLink(item: invite.url) { Label("Envoyer le lien", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered)
                    Text("Dans La Réplique : Rejoindre une pièce, puis ce code.")
                        .font(.caption).foregroundStyle(Theme.inkFaint)
                }
            }
        } else {
            Label("Seule la personne qui a partagé la pièce peut inviter.", systemImage: "person.badge.key")
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private var signedName: String {
        if case .success(let n) = Notes.validName(name) { return n }; return ""
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task { @MainActor in
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
        copied = true
        Task { @MainActor in try? await Task.sleep(for: .seconds(1.6)); copied = false }
    }
}

// MARK: - Join

struct JoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onJoined: (UUID) -> Void
    @AppStorage("notes.authorName") private var name = ""
    @ObservedObject private var auth = CollabAuth.shared
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    private var ready: Bool {
        if case .success = Notes.validName(name) { return code.trimmingCharacters(in: .whitespaces).count >= 6 }; return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                  if !auth.isSignedIn {
                    CollabSignInView()
                  } else {
                    FieldGroup("Code ou lien d'invitation") {
                        TextField("ABCDE23456", text: $code).sheetField()
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            #endif
                    }
                    FieldGroup("Ton nom, pour les autres") { TextField("Ton nom", text: $name).sheetField() }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(Theme.rose)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        busy = true; error = nil
                        Task { @MainActor in
                            do {
                                guard case .success(let n) = Notes.validName(name) else { return }
                                let id = try await CollabService.join(code: code.uppercased().contains("/") ? code : code.uppercased(), as: n)
                                dismiss(); onJoined(id)
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: { Label("Rejoindre", systemImage: "person.2.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!ready || busy)
                    .overlay { if busy { ProgressView().controlSize(.small) } }
                  }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Rejoindre une pièce")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 440, height: 520)
        #endif
        .onAppear { if name.isEmpty { name = auth.person?.name ?? "" } }
    }
}

// MARK: - Members

/// Who is in the play. The owner changes roles and removes people; anyone else
/// may leave.
private struct MembersSection: View {
    let link: CollabLink
    var onLeft: () -> Void
    @StateObject private var store: MembersStore
    @State private var error: String?
    @State private var confirmLeave = false

    init(link: CollabLink, onLeft: @escaping () -> Void) {
        self.link = link; self.onLeft = onLeft
        _store = StateObject(wrappedValue: MembersStore(playID: link.remoteID))
    }

    private var iOwn: Bool { link.ownerUid == CollabBackend.uid }

    var body: some View {
        FieldGroup("Autour de la pièce") {
            ForEach(store.members) { m in
                HStack(spacing: 10) {
                    Text(String(m.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color(hexString: PresenceChannel.color(for: m.id)), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name + (m.id == CollabBackend.uid ? String(localized: " (toi)") : "")).foregroundStyle(.white)
                        if m.id == link.ownerUid { Text("a partagé la pièce").font(.caption).foregroundStyle(Theme.inkFaint) }
                    }
                    Spacer()
                    if iOwn, m.id != link.ownerUid {
                        Menu {
                            Picker("Rôle", selection: Binding(get: { m.role }, set: { r in act { try await store.setRole(r, for: m.id) } })) {
                                Text("Écrire").tag("writer"); Text("Commenter").tag("commenter"); Text("Lire").tag("reader")
                            }
                            Divider()
                            Button("Retirer de la pièce", systemImage: "person.badge.minus", role: .destructive) { act { try await store.remove(m.id) } }
                        } label: { roleLabel(m.role) }
                        .menuStyle(.borderlessButton).fixedSize()
                    } else {
                        roleLabel(m.role)
                    }
                }
                .padding(.vertical, 3)
            }
            if !iOwn {
                Button("Quitter cette pièce", role: .destructive) { confirmLeave = true }.buttonStyle(.bordered)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.rose) }
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .confirmationDialog("Quitter cette pièce ? Elle disparaîtra de cet appareil ; il te faudra une nouvelle invitation pour revenir.",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Quitter", role: .destructive) { act { try await CollabService.leave(link); onLeft() } }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func roleLabel(_ role: String) -> some View {
        Text(role == "writer" ? "Écrire" : role == "commenter" ? "Commenter" : "Lire")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.gelBright)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.gel.opacity(0.16), in: Capsule())
    }

    private func act(_ op: @escaping () async throws -> Void) {
        error = nil
        Task { @MainActor in do { try await op() } catch { self.error = error.localizedDescription } }
    }
}
