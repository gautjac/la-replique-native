import SwiftUI

// « Chercher » — a find bar over the script: type, see « 3 / 12 », walk the
// results with ⌘G / ⇧⌘G (or the arrows), and the matching words are selected
// in the line itself. Case- and accent-insensitive: « ile » finds « île ».

/// Where a find result sits: which block, which field, which characters.
struct FindHit: Equatable {
    enum Field: Equatable { case text, label }
    var id: UUID
    var field: Field
    /// Character offsets into the field's text at the time of the search.
    var lower: Int
    var upper: Int
    /// Bumps on every move — even back to the same hit — so a row reacts each time.
    var token: Int
    /// Focus the line and select the words (Return / ⌘G / arrows). While the query
    /// is being typed the hit only scrolls and rings: focus must stay in the bar.
    var select: Bool

    func range(in s: String) -> Range<String.Index>? {
        guard lower >= 0, lower < upper, upper <= s.count else { return nil }
        return s.index(s.startIndex, offsetBy: lower)..<s.index(s.startIndex, offsetBy: upper)
    }
}

@MainActor
final class FindState: ObservableObject {
    struct Match: Equatable {
        var id: UUID
        var field: FindHit.Field
        var lower: Int
        var upper: Int
    }

    @Published var query = ""
    @Published var isPresented = false
    @Published private(set) var matches: [Match] = []
    @Published private(set) var index: Int?
    @Published private(set) var hit: FindHit?
    private var token = 0

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The searchable text of a block: its label for acts and scenes, its text otherwise.
    static func field(of el: Element) -> (String, FindHit.Field) {
        switch el.kind {
        case .act, .scene: return (el.label ?? "", .label)
        default: return (el.text ?? "", .text)
        }
    }

    /// Every occurrence, in reading order. Empty query → nothing.
    static func find(_ query: String, in play: Play) -> [Match] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var out: [Match] = []
        for el in play.elementList {
            let (s, field) = field(of: el)
            var from = s.startIndex
            while from < s.endIndex, let r = s.range(of: q, options: options, range: from..<s.endIndex) {
                out.append(Match(id: el.id, field: field, lower: s.distance(from: s.startIndex, to: r.lowerBound),
                                 upper: s.distance(from: s.startIndex, to: r.upperBound)))
                from = r.upperBound == r.lowerBound ? s.index(after: r.lowerBound) : r.upperBound
            }
        }
        return out
    }

    /// Re-run the search. With `jump`, land on the first result (typing); otherwise
    /// stay on the current one if it still exists.
    func rebuild(_ play: Play, jump: Bool) {
        let current = index.flatMap { matches.indices.contains($0) ? matches[$0] : nil }
        matches = Self.find(query, in: play)
        guard !matches.isEmpty else { index = nil; hit = nil; return }
        if jump {
            index = 0; go(select: false)
        } else if let current, let i = matches.firstIndex(of: current) {
            index = i
        } else {
            index = min(index ?? 0, matches.count - 1)
        }
    }

    func next(_ play: Play) { step(play, by: 1) }
    func previous(_ play: Play) { step(play, by: -1) }

    private func step(_ play: Play, by delta: Int) {
        rebuild(play, jump: false)
        guard !matches.isEmpty else { return }
        let n = matches.count
        index = ((index ?? (delta > 0 ? -1 : 0)) + delta + n) % n
        go(select: true)
    }

    private func go(select: Bool) {
        guard let i = index, matches.indices.contains(i) else { hit = nil; return }
        token += 1
        let m = matches[i]
        hit = FindHit(id: m.id, field: m.field, lower: m.lower, upper: m.upper, token: token, select: select)
    }

    func open() { isPresented = true }
    func close() { isPresented = false; hit = nil; index = nil; matches = [] }
}

struct FindBar: View {
    @ObservedObject var find: FindState
    let play: Play
    /// Bumped by ⌘F / the toolbar button: put the cursor back in the field.
    var focusRequest: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint)
            TextField("Chercher dans la pièce", text: $find.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { find.next(play) }
                #if os(macOS)
                .onExitCommand { find.close() }
                #endif
            Text(count)
                .font(.caption.monospacedDigit())
                .foregroundStyle(find.matches.isEmpty && !find.query.isEmpty ? Theme.rose : Theme.inkFaint)
                .lineLimit(1).fixedSize()
            Button { find.previous(play) } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(find.matches.isEmpty)
                .help("Précédent (⇧⌘G)")
                .accessibilityLabel(Text("Résultat précédent"))
            Button { find.next(play) } label: { Image(systemName: "chevron.down") }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(find.matches.isEmpty)
                .help("Suivant (⌘G)")
                .accessibilityLabel(Text("Résultat suivant"))
            Button { find.close() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint) }
                .help("Fermer la recherche")
                .accessibilityLabel(Text("Fermer la recherche"))
        }
        .buttonStyle(.plain)
        .font(.body)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.deskLight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
    }

    private var count: String {
        if find.query.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        if find.matches.isEmpty { return String(localized: "Aucun résultat") }
        return "\((find.index ?? 0) + 1) / \(find.matches.count)"
    }
}

/// A text field that can select a find hit inside itself (iOS 18 / macOS 15:
/// `TextField(selection:)`). Older systems fall back to a plain field; the row's
/// ring still shows where the hit is.
@available(iOS 18, macOS 15, *)
struct FindableTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var axis: Axis = .horizontal
    /// The current hit, only when it targets THIS field.
    var hit: FindHit?
    @State private var selection: TextSelection?

    var body: some View {
        TextField(placeholder, text: $text, selection: $selection, axis: axis)
            .onAppear { apply() }
            .onChange(of: hit?.token) { _, _ in apply() }
    }

    private func apply() {
        guard let hit, hit.select, let r = hit.range(in: text) else { return }
        // After focus lands (the parent focuses the line in the same update).
        DispatchQueue.main.async { selection = TextSelection(range: r) }
    }
}
