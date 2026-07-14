import SwiftUI

/// The app's interface language, overriding the system default per-app via the
/// standard `AppleLanguages` key. Takes effect on the next launch (the
/// Apple-sanctioned, non-hacky path — no bundle swizzling).
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, fr, en
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "Système")
        case .fr: return "Français"
        case .en: return "English"
        }
    }

    static var current: InterfaceLanguage {
        guard let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = langs.first else { return .system }
        if first.hasPrefix("en") { return .en }
        if first.hasPrefix("fr") { return .fr }
        return .system
    }

    func apply() {
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .fr: UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
        case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }
}

/// Segmented Système / Français / English picker with an "applies next launch" note.
struct LanguagePicker: View {
    @State private var sel = InterfaceLanguage.current
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $sel) {
                ForEach(InterfaceLanguage.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: sel) { _, v in v.apply() }
            Text("Prend effet au prochain lancement.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
