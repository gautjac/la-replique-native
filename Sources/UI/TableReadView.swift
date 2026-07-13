import SwiftUI
import AVFoundation

/// A table read — each character voiced by a distinct system voice
/// (AVSpeechSynthesizer, on-device). ElevenLabs (BYOK) is a later layer.
@MainActor
final class TableReader: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    struct Item: Identifiable { let id = UUID(); let name: String?; let color: String?; let text: String; let voiceIndex: Int; let narrator: Bool }

    @Published var index = 0
    @Published var playing = false
    private let synth = AVSpeechSynthesizer()
    private(set) var items: [Item] = []
    private var lang: Lang = .fr

    override init() { super.init(); synth.delegate = self }

    func load(_ play: Play) {
        lang = play.lang
        let charIndex = Dictionary(uniqueKeysWithValues: play.characterList.enumerated().map { ($1.id.uuidString, $0) })
        items = play.elementList.compactMap { el in
            switch el.kind {
            case .act, .scene:
                let label = (el.label ?? "") + (el.kind == .scene && (el.setting?.isEmpty == false) ? " — \(el.setting!)" : "")
                return Item(name: nil, color: nil, text: label, voiceIndex: 0, narrator: true)
            case .stage:
                guard let t = el.text, !t.isEmpty else { return nil }
                return Item(name: nil, color: nil, text: t, voiceIndex: 0, narrator: true)
            case .cue:
                guard let t = el.text, !t.isEmpty else { return nil }
                let c = play.character(id: el.characterID)
                return Item(name: c?.name, color: c?.colorHex, text: t,
                            voiceIndex: charIndex[el.characterID ?? ""] ?? 0, narrator: false)
            case .action:
                guard let t = el.text, !t.isEmpty else { return nil }
                return Item(name: nil, color: nil, text: t, voiceIndex: 0, narrator: false)
            }
        }
    }

    private var voices: [AVSpeechSynthesisVoice] {
        let prefix = lang == .fr ? "fr" : "en"
        let matched = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return matched.isEmpty ? AVSpeechSynthesisVoice.speechVoices() : matched
    }

    func play() { playing = true; speak(from: index) }
    func pause() { playing = false; synth.stopSpeaking(at: .immediate) }
    func goto(_ i: Int) { index = max(0, min(i, items.count - 1)); if playing { synth.stopSpeaking(at: .immediate); speak(from: index) } }

    private func speak(from i: Int) {
        guard i < items.count else { playing = false; return }
        index = i
        let it = items[i]
        let u = AVSpeechUtterance(string: it.text)
        let vs = voices
        if !vs.isEmpty { u.voice = it.narrator ? vs[vs.count - 1] : vs[it.voiceIndex % vs.count] }
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.playing { self.speak(from: self.index + 1) } }
    }
}

struct TableReadView: View {
    @Environment(\.dismiss) private var dismiss
    let play: Play
    @StateObject private var reader = TableReader()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(reader.items.enumerated()), id: \.element.id) { i, it in
                            row(i, it).id(i)
                        }
                    }.padding(18)
                }
                .onChange(of: reader.index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
            .background(Theme.desk)
            .navigationTitle("Lecture à voix")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { reader.pause(); dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) { controls }
            }
            .onAppear { reader.load(play) }
            .onDisappear { reader.pause() }
        }
        #if os(macOS)
        .frame(width: 560, height: 680)
        #endif
    }

    @ViewBuilder private func row(_ i: Int, _ it: TableReader.Item) -> some View {
        let active = i == reader.index
        if let name = it.name {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Color(hexString: it.color))
                Text(it.text).font(.body).foregroundStyle(active ? .white : Theme.inkFaint)
            }.padding(8).background(active ? Theme.deskLight : .clear, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text(it.text).font(.callout).italic().foregroundStyle(active ? .white : Theme.inkFaint).padding(.leading, 8)
        }
    }

    private var controls: some View {
        HStack {
            Button { reader.goto(reader.index - 1) } label: { Image(systemName: "backward.fill") }
            Button { reader.playing ? reader.pause() : reader.play() } label: {
                Image(systemName: reader.playing ? "pause.fill" : "play.fill").font(.title2)
            }
            Button { reader.goto(reader.index + 1) } label: { Image(systemName: "forward.fill") }
            Spacer()
            Text("\(min(reader.index + 1, reader.items.count)) / \(reader.items.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
