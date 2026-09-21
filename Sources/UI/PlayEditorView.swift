import SwiftUI
import SwiftData

/// P1 — the editable script surface. Keyboard-driven on Mac/iPad (Return = new
/// réplique · Tab = change block type · name+space/colon = switch speaker · ⌫ on
/// an empty block = delete); a keyboard toolbar drives the same on iPhone.
///
/// Performance shape (2026-09-12): every block is its own `ElementRow` view, so
/// SwiftUI's Observation scopes a keystroke to the ONE row whose `Element`
/// changed. Before, rows were built inline in this body — a keystroke on a
/// 1500-element play re-sorted the play and rebuilt all 1500 rows (measured:
/// 1.5–4 s per keystroke on the simulator). The page is a LazyVStack, so a parent
/// re-render (focus/hint change) re-runs only the rows on screen.
struct PlayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    @Binding var jumpTarget: UUID?
    /// Open readers' notes per element id (empty when the play isn't shared).
    var noteCounts: [String: Int] = [:]
    /// A margin badge was tapped.
    var onShowNotes: (UUID) -> Void = { _ in }
    /// Other people in this shared play, by the element their cursor is in.
    var others: [String: [PresencePerson]] = [:]
    /// The cursor moved to another block (nil = nowhere) — feeds presence.
    var onFocusChange: (UUID?) -> Void = { _ in }
    /// Readers and commenters: nothing can be typed — but the page must still SCROLL.
    /// So this disables the page's CONTENT, never the ScrollView around it (disabling
    /// a ScrollView disables its scrolling: Jac's iPad, 2026-09-21).
    var readOnly = false
    /// This is a shared play and I may leave notes: offer it on the line I'm in (a
    /// writer), or on any line I tap (a commenter, who cannot place a cursor).
    var notesEnabled = false
    @FocusState private var focused: UUID?

    @State private var newCharName = ""
    @State private var newCharTarget: UUID?
    /// Live speaker autocomplete for the focused cue (prefix match on the cast).
    @State private var speakerHint: SpeakerHint?
    #if os(macOS)
    @StateObject private var tabMonitor = TabKeyMonitor()
    #else
    @StateObject private var editorFocus = EditorFocus()
    #endif

    /// Find one element WITHOUT sorting the play. `elementList` sorts on every
    /// access — fine once per render, wasteful for a single lookup.
    private func element(_ id: UUID?) -> Element? {
        guard let id else { return nil }
        return (play.elements ?? []).first { $0.id == id }
    }
    private var focusedElement: Element? { element(focused) }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock.disabled(readOnly)
                    page
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.vertical, 28)
            }
            .background(Theme.desk)
            .onChange(of: focused) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                #if os(iOS)
                editorFocus.id = id
                #endif
                if let h = speakerHint, h.el != id { speakerHint = nil }
                onFocusChange(id)
            }
            .onChange(of: jumpTarget) { _, target in
                // The stack is lazy: bring the block into existence first, then
                // focus it once its field is there.
                guard let target else { return }
                jumpTarget = nil
                proxy.scrollTo(target, anchor: .center)
                DispatchQueue.main.async { focused = target }
            }
        }
        #if os(iOS)
        .toolbar { keyboardToolbar }
        #endif
    }

    /// On iOS the scroll body is wrapped so a hardware Tab can be intercepted.
    @ViewBuilder private var editorBody: some View {
        #if os(iOS)
        KeyCommandHost(onTab: {
            guard let id = editorFocus.id, let el = element(id) else { return }
            Editing.convert(el, to: Editing.cycleKind(el.kind), play: play, context: context)
            // Re-focus after the row rebuilds, else the next Tab has no focused block.
            DispatchQueue.main.async { focused = id }
        }) { scrollBody }
        #else
        scrollBody
        #endif
    }

    var body: some View {
        editorBody
        .navigationTitle(play.title.isEmpty ? String(localized: "Pièce sans titre") : play.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Nouveau personnage", isPresented: Binding(get: { newCharTarget != nil }, set: { if !$0 { newCharTarget = nil } })) {
            TextField("Nom", text: $newCharName)
            Button("Ajouter") { commitNewCharacter() }
            Button("Annuler", role: .cancel) { newCharTarget = nil; newCharName = "" }
        }
        #if os(macOS)
        // Tab cycles the focused block's type (AppKit would otherwise steal Tab
        // for focus traversal before SwiftUI's key handler runs).
        .onAppear {
            let focusBinding = $focused
            tabMonitor.focusedID = focused
            tabMonitor.onCycle = { id in
                guard let el = (play.elements ?? []).first(where: { $0.id == id }) else { return }
                Editing.convert(el, to: Editing.cycleKind(el.kind), play: play, context: context)
                // Re-focus after the row rebuilds, else the next Tab has no focused block.
                DispatchQueue.main.async { focusBinding.wrappedValue = id }
            }
            tabMonitor.start()
        }
        .onDisappear { tabMonitor.stop() }
        .onChange(of: focused) { _, id in tabMonitor.focusedID = id }
        #endif
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Titre", text: $play.title)
                .font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                .textFieldStyle(.plain)
            HStack {
                TextField("Sous-titre", text: $play.subtitle)
                    .foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
                TextField("Autrice / auteur", text: $play.author)
                    .foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.bottom, 18)
        .onChange(of: play.title) { _, _ in play.touch() }
    }

    // MARK: Page

    private var page: some View {
        // Sort ONCE per render — `elementList` sorts on every access. This body
        // only re-runs on structural change (insert/remove/reorder), focus, or a
        // speaker-hint change; keystrokes are absorbed by the rows.
        let els = play.elementList
        #if DEBUG
        RenderCounter.page(els.count)
        #endif
        let actions = RowActions(
            enter: onEnter, tab: onTab, backspace: onBackspace,
            textChanged: { el, v in handleTypeAhead(el, v); updateSpeakerHint(el, v) },
            acceptHint: acceptSpeakerHint,
            newCharacter: { el in newCharTarget = el.id },
            showNotes: { el in onShowNotes(el.id) })
        // Lazy: only the blocks on screen exist as views. A 1500-line play used
        // to instantiate 1500 text fields, and any environment change (window
        // activation, resize, keyboard) re-ran every one of them (~1.5 s).
        return LazyVStack(alignment: .leading, spacing: 2) {
            if els.isEmpty {
                VStack(spacing: 14) {
                    Text("La page est vide. Commence par une réplique.").foregroundStyle(Theme.inkFaint)
                    Button("Écrire la première réplique") { startWriting() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(els) { el in
                    ElementRow(el: el, play: play, focus: $focused,
                               hint: speakerHint?.el == el.id ? speakerHint : nil,
                               noteCount: noteCounts[el.id.uuidString] ?? 0,
                               others: others[el.id.uuidString] ?? [],
                               readOnly: readOnly, notesEnabled: notesEnabled,
                               actions: actions)
                        .id(el.id)
                }
            }
            Text("Entrée : nouvelle réplique · Tab : changer le type · Nom + espace/« : » : personnage · ⌫ : supprimer")
                .font(.caption2).foregroundStyle(Theme.inkFaint.opacity(0.7))
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Keyboard toolbar (iPhone / iPad on-screen)

    #if os(iOS)
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
          // Only while a BLOCK of the script has the cursor: a keyboard toolbar is
          // scene-wide, and these buttons used to show up over the notes sheet too.
          if focused != nil {
            Button { if let el = focusedElement { onEnter(el) } } label: { Label("Réplique", systemImage: "return") }
            Button { if let el = focusedElement { onTab(el) } } label: { Label("Type", systemImage: "arrow.2.squarepath") }
            if let el = focusedElement, el.kind == .cue {
                Menu {
                    ForEach(play.characterList) { c in
                        Button(c.name) { el.characterID = c.id.uuidString; play.touch() }
                    }
                    Divider()
                    Button("Nouveau personnage…") { newCharTarget = el.id }
                } label: { Label("Personnage", systemImage: "person") }
            }
            Spacer()
            Button("OK") { focused = nil }
          }
        }
    }
    #endif

    // MARK: Ops

    private func startWriting() {
        let el = Editing.insert(.cue, after: nil, play: play, context: context)
        focused = el.id
    }
    private func onEnter(_ el: Element) {
        // If a speaker suggestion is showing for this cue, Return picks it
        // (and drops you into the line) instead of starting a new réplique.
        if speakerHint?.el == el.id {
            acceptSpeakerHint(el)
            return
        }
        let other = Editing.alternateSpeaker(play, after: el)
        let new = Editing.insert(.cue, after: el, play: play, context: context, speaker: other)
        focused = new.id
    }

    /// Show/refresh the speaker suggestion while the cue's line is a single
    /// leading token that prefixes an existing character. Only writes the state
    /// when it actually changes — a parent re-render is not free.
    private func updateSpeakerHint(_ el: Element, _ value: String) {
        guard el.kind == .cue,
              !value.isEmpty, !value.contains(" "), !value.contains("\n"),
              let match = Editing.suggestSpeaker(play, prefix: value) else {
            if speakerHint?.el == el.id { speakerHint = nil }
            return
        }
        let hint = SpeakerHint(el: el.id, charID: match.id, name: match.name)
        if speakerHint != hint { speakerHint = hint }
    }

    /// Assign the suggested speaker, clear the typed prefix, and stay in the line.
    private func acceptSpeakerHint(_ el: Element) {
        guard let hint = speakerHint, hint.el == el.id,
              let c = (play.characters ?? []).first(where: { $0.id == hint.charID }) else { return }
        el.characterID = c.id.uuidString
        el.text = ""
        play.touch()
        speakerHint = nil
        focused = el.id
    }
    /// Cycle a block's type in place (no focus change) — shared by the Tab key
    /// intercepts (macOS monitor / iOS key command) and the toolbar button.
    private func cycleType(_ el: Element) {
        Editing.convert(el, to: Editing.cycleKind(el.kind), play: play, context: context)
    }
    private func onTab(_ el: Element) {
        cycleType(el)
        // Cycling replaces the row's view, so SwiftUI drops focus as the old
        // field disappears; re-assert it on the next tick, once the new field exists.
        let id = el.id
        DispatchQueue.main.async { focused = id }
    }
    private func onBackspace(_ el: Element) {
        let prev = Editing.remove(el, play: play, context: context)
        focused = prev?.id
    }
    private func handleTypeAhead(_ el: Element, _ value: String) {
        guard el.kind == .cue, let last = value.last, last == " " || last == ":" else { return }
        let token = String(value.dropLast())
        guard !token.isEmpty, !token.contains(" ") else { return }
        _ = Editing.typeAhead(el, token: token, allowCreate: last == ":", play: play, context: context)
    }
    private func commitNewCharacter() {
        defer { newCharName = ""; newCharTarget = nil }
        let name = newCharName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let el = element(newCharTarget) else { return }
        let c = Editing.addCharacter(play, name: name.uppercased(), context: context)
        el.characterID = c.id.uuidString
    }
}

// MARK: - Speaker autocomplete

/// A live speaker suggestion for a cue being typed (prefix match on the cast).
private struct SpeakerHint: Equatable, Sendable {
    let el: UUID
    let charID: UUID
    let name: String
}

/// What a row can ask its editor to do. One value per page render, shared by
/// every row (closures aren't comparable, so `ElementRow ==` ignores it).
private struct RowActions {
    var enter: (Element) -> Void
    var tab: (Element) -> Void
    var backspace: (Element) -> Void
    var textChanged: (Element, String) -> Void
    var acceptHint: (Element) -> Void
    var newCharacter: (Element) -> Void
    var showNotes: (Element) -> Void
}

// MARK: - One block of the script

/// One element of the play as an editable row. Its body reads only ITS element
/// (plus the cast, for the speaker), so Observation re-runs it — and nothing
/// else — when that element changes.
private struct ElementRow: View {
    let el: Element
    let play: Play
    var focus: FocusState<UUID?>.Binding
    let hint: SpeakerHint?
    /// Open readers' notes anchored to this block (0 = no badge).
    let noteCount: Int
    /// Other people whose cursor is in this block right now.
    var others: [PresencePerson] = []
    var readOnly = false
    var notesEnabled = false
    let actions: RowActions

    /// Soft lock: while someone else is in this line, I can read it change but not
    /// type in it — unless I was already in it (then last writer wins, as ever).
    private var lockedBy: PresencePerson? { focus.wrappedValue == el.id ? nil : others.first }

    // No Equatable skip here any more (2026-09-21). It paid for itself when the
    // page was a plain VStack of every block; the page is lazy now, so a parent
    // pass only re-runs the dozen rows on screen. And a collaborative play gets
    // changes from OUTSIDE the view tree — a skipped body is exactly the wrong
    // optimisation to have near those.

    var body: some View {
        #if DEBUG
        let _ = RenderCounter.row(el.id)
        #endif
        block
            // Disabled per ROW (never the ScrollView): read-only people scroll, and a tap
            // on a line still reaches the gesture below.
            .disabled(lockedBy != nil || readOnly)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if readOnly && notesEnabled { actions.showNotes(el) } }
            .overlay(alignment: .leading) {
                if let who = others.first {
                    Rectangle().fill(Color(hexString: who.colorHex)).frame(width: 3).offset(x: -14)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !others.isEmpty {
                    Text(others.map(\.name).joined(separator: ", "))
                        .font(.system(size: 10, weight: .bold)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hexString: others[0].colorHex), in: Capsule())
                        .foregroundStyle(.white)
                        .offset(y: 4)
                        .accessibilityLabel(Text("\(others.map(\.name).joined(separator: ", ")) écrit ici"))
                }
            }
            .overlay(alignment: .topTrailing) {
                if noteCount > 0 {
                    Button { actions.showNotes(el) } label: { NoteBadge(count: noteCount) }
                        .buttonStyle(.plain)
                        .offset(x: 22, y: 6)
                } else if notesEnabled, !readOnly, focus.wrappedValue == el.id {
                    // The line I'm in: one tap to leave a note on it.
                    Button { actions.showNotes(el) } label: {
                        Image(systemName: "plus.bubble").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.gel).padding(4)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 24, y: 2)
                    .accessibilityLabel(Text("Laisser une note sur cette ligne"))
                }
            }
    }

    @ViewBuilder private var block: some View {
        switch el.kind {
        case .act:
            HStack(spacing: 12) {
                Rectangle().fill(Theme.paperShade).frame(height: 1)
                TextField("", text: text(\.label))
                    .font(.system(size: 16, weight: .bold)).kerning(3).foregroundStyle(Theme.ink)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).fixedSize()
                    .focused(focus, equals: el.id)
                    .modifier(keys(isEmpty: (el.label ?? "").isEmpty))
                Rectangle().fill(Theme.paperShade).frame(height: 1)
            }.padding(.vertical, 16)

        case .scene:
            VStack(alignment: .leading, spacing: 3) {
                TextField("SCÈNE", text: text(\.label))
                    .font(.system(size: 15, weight: .bold)).kerning(2).foregroundStyle(Theme.ink)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: el.id)
                    .modifier(keys(isEmpty: (el.label ?? "").isEmpty))
                TextField("Lieu, moment… (facultatif)", text: text(\.setting))
                    .font(.subheadline).foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
            }.padding(.top, 16).padding(.bottom, 8)

        case .stage:
            TextField("Ce qui se passe sur scène…", text: text(\.text), axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.inkSoft).textFieldStyle(.plain)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.gel.opacity(0.55)).frame(width: 2) }
                .padding(.vertical, 8)
                .focused(focus, equals: el.id)
                .modifier(keys(isEmpty: (el.text ?? "").isEmpty))

        case .action:
            TextField("Action…", text: text(\.text), axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.ink).textFieldStyle(.plain)
                .padding(.vertical, 6)
                .focused(focus, equals: el.id)
                .modifier(keys(isEmpty: (el.text ?? "").isEmpty))

        case .cue:
            let ch = play.character(id: el.characterID)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    speakerMenu(current: ch)
                    if let hint {
                        Button { actions.acceptHint(el) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "return")
                                Text(hint.name.uppercased())
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.gel.opacity(0.16), in: Capsule())
                            .foregroundStyle(Theme.gelBright)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                    TextField("jeu", text: text(\.parenthetical))
                        .font(.subheadline).foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
                }
                TextField("Sa réplique…", text: text(\.text), axis: .vertical)
                    .font(.system(size: 18)).foregroundStyle(Theme.ink).textFieldStyle(.plain)
                    .focused(focus, equals: el.id)
                    .modifier(keys(isEmpty: (el.text ?? "").isEmpty))
                    .onChange(of: el.text ?? "") { _, newValue in actions.textChanged(el, newValue) }
            }.padding(.vertical, 8)
        }
    }

    private func speakerMenu(current: Character?) -> some View {
        Menu {
            ForEach(play.characterList) { c in
                Button(c.name) { el.characterID = c.id.uuidString; play.touch() }
            }
            Divider()
            Button("Nouveau personnage…") { actions.newCharacter(el) }
        } label: {
            Text(current?.name.uppercased() ?? "+ PERSONNAGE")
                .font(.system(size: 15, weight: .bold)).kerning(2)
                .foregroundStyle(Color(hexString: current?.colorHex))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func keys(isEmpty: Bool) -> EditorKeys {
        EditorKeys(isEmpty: isEmpty,
                   onEnter: { actions.enter(el) },
                   onTab: { actions.tab(el) },
                   onBackspace: { actions.backspace(el) })
    }

    // A Binding<String> onto an optional String? model field.
    private func text(_ key: ReferenceWritableKeyPath<Element, String?>) -> Binding<String> {
        Binding(get: { el[keyPath: key] ?? "" }, set: {
            #if DEBUG
            RenderCounter.log.debug("set \(el.id.uuidString.prefix(8), privacy: .public)")
            #endif
            el[keyPath: key] = $0; play.touch()
        })
    }
}

// MARK: - Editor key handling

private struct EditorKeys: ViewModifier {
    let isEmpty: Bool
    let onEnter: () -> Void
    let onTab: () -> Void
    let onBackspace: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(keys: [.return, .tab, .delete]) { press in
                if press.key == .return {
                    if press.modifiers.contains(.shift) { return .ignored }
                    onEnter(); return .handled
                } else if press.key == .tab {
                    onTab(); return .handled
                } else if press.key == .delete {
                    if isEmpty { onBackspace(); return .handled }
                    return .ignored
                }
                return .ignored
            }
    }
}
