import SwiftUI
import SwiftData

/// P1 — the editable script surface. Keyboard-driven on Mac/iPad (Return = new
/// réplique · Tab = change block type · name+space/colon = switch speaker · ⌫ on
/// an empty block = delete); a keyboard toolbar drives the same on iPhone.
struct PlayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var play: Play
    @Binding var jumpTarget: UUID?
    @FocusState private var focused: UUID?

    @State private var newCharName = ""
    @State private var newCharTarget: UUID?
    #if os(macOS)
    @StateObject private var tabMonitor = TabKeyMonitor()
    #else
    @StateObject private var editorFocus = EditorFocus()
    #endif

    private var elements: [Element] { play.elementList }
    private var focusedElement: Element? { elements.first { $0.id == focused } }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
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
            }
            .onChange(of: jumpTarget) { _, target in
                if let target { focused = target; jumpTarget = nil }
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
            guard let id = editorFocus.id, let el = play.elementList.first(where: { $0.id == id }) else { return }
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
        .navigationTitle(play.title.isEmpty ? "Pièce sans titre" : play.title)
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
                guard let el = play.elementList.first(where: { $0.id == id }) else { return }
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
        VStack(alignment: .leading, spacing: 2) {
            if elements.isEmpty {
                VStack(spacing: 14) {
                    Text("La page est vide. Commence par une réplique.").foregroundStyle(Theme.inkFaint)
                    Button("Écrire la première réplique") { startWriting() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(elements) { el in
                    row(el).id(el.id)
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

    // MARK: Rows

    @ViewBuilder
    private func row(_ el: Element) -> some View {
        switch el.kind {
        case .act:
            HStack(spacing: 12) {
                Rectangle().fill(Theme.paperShade).frame(height: 1)
                TextField("", text: text(el, \.label))
                    .font(.system(size: 16, weight: .bold)).kerning(3).foregroundStyle(Theme.ink)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).fixedSize()
                    .focused($focused, equals: el.id)
                    .editorKeys(isEmpty: (el.label ?? "").isEmpty, el: el, onEnter: { onEnter(el) }, onTab: { onTab(el) }, onBackspace: { onBackspace(el) })
                Rectangle().fill(Theme.paperShade).frame(height: 1)
            }.padding(.vertical, 16)

        case .scene:
            VStack(alignment: .leading, spacing: 3) {
                TextField("SCÈNE", text: text(el, \.label))
                    .font(.system(size: 15, weight: .bold)).kerning(2).foregroundStyle(Theme.ink)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: el.id)
                    .editorKeys(isEmpty: (el.label ?? "").isEmpty, el: el, onEnter: { onEnter(el) }, onTab: { onTab(el) }, onBackspace: { onBackspace(el) })
                TextField("Lieu, moment… (facultatif)", text: text(el, \.setting))
                    .font(.subheadline).foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
            }.padding(.top, 16).padding(.bottom, 8)

        case .stage:
            TextField("Ce qui se passe sur scène…", text: text(el, \.text), axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.inkSoft).textFieldStyle(.plain)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.gel.opacity(0.55)).frame(width: 2) }
                .padding(.vertical, 8)
                .focused($focused, equals: el.id)
                .editorKeys(isEmpty: (el.text ?? "").isEmpty, el: el, onEnter: { onEnter(el) }, onTab: { onTab(el) }, onBackspace: { onBackspace(el) })

        case .action:
            TextField("Action…", text: text(el, \.text), axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.ink).textFieldStyle(.plain)
                .padding(.vertical, 6)
                .focused($focused, equals: el.id)
                .editorKeys(isEmpty: (el.text ?? "").isEmpty, el: el, onEnter: { onEnter(el) }, onTab: { onTab(el) }, onBackspace: { onBackspace(el) })

        case .cue:
            let ch = play.character(id: el.characterID)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    speakerMenu(el, current: ch)
                    TextField("jeu", text: text(el, \.parenthetical))
                        .font(.subheadline).foregroundStyle(Theme.inkFaint).textFieldStyle(.plain)
                }
                TextField("Sa réplique…", text: text(el, \.text), axis: .vertical)
                    .font(.system(size: 18)).foregroundStyle(Theme.ink).textFieldStyle(.plain)
                    .focused($focused, equals: el.id)
                    .editorKeys(isEmpty: (el.text ?? "").isEmpty, el: el, onEnter: { onEnter(el) }, onTab: { onTab(el) }, onBackspace: { onBackspace(el) })
                    .onChange(of: el.text ?? "") { _, newValue in handleTypeAhead(el, newValue) }
            }.padding(.vertical, 8)
        }
    }

    private func speakerMenu(_ el: Element, current: Character?) -> some View {
        Menu {
            ForEach(play.characterList) { c in
                Button(c.name) { el.characterID = c.id.uuidString; play.touch() }
            }
            Divider()
            Button("Nouveau personnage…") { newCharTarget = el.id }
        } label: {
            Text(current?.name.uppercased() ?? "+ PERSONNAGE")
                .font(.system(size: 15, weight: .bold)).kerning(2)
                .foregroundStyle(Color(hexString: current?.colorHex))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    // MARK: Keyboard toolbar (iPhone / iPad on-screen)

    #if os(iOS)
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
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
    #endif

    // MARK: Ops

    private func startWriting() {
        let el = Editing.insert(.cue, after: nil, play: play, context: context)
        focused = el.id
    }
    private func onEnter(_ el: Element) {
        let other = Editing.alternateSpeaker(play, after: el)
        let new = Editing.insert(.cue, after: el, play: play, context: context, speaker: other)
        focused = new.id
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
        guard !name.isEmpty, let id = newCharTarget, let el = elements.first(where: { $0.id == id }) else { return }
        let c = Editing.addCharacter(play, name: name.uppercased(), context: context)
        el.characterID = c.id.uuidString
    }

    // A Binding<String> onto an optional String? model field.
    private func text(_ el: Element, _ key: ReferenceWritableKeyPath<Element, String?>) -> Binding<String> {
        Binding(get: { el[keyPath: key] ?? "" }, set: { el[keyPath: key] = $0; play.touch() })
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

private extension View {
    func editorKeys(isEmpty: Bool, el: Element, onEnter: @escaping () -> Void, onTab: @escaping () -> Void, onBackspace: @escaping () -> Void) -> some View {
        modifier(EditorKeys(isEmpty: isEmpty, onEnter: onEnter, onTab: onTab, onBackspace: onBackspace))
    }
}
