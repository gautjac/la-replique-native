import SwiftUI
import ObjectiveC

/// The app's interface language, switched live (no relaunch).
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

    /// The .lproj resource name to load, or nil to follow the system.
    var lproj: String? {
        switch self { case .system: return nil; case .fr: return "fr"; case .en: return "en" }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .fr: return Locale(identifier: "fr")
        case .en: return Locale(identifier: "en")
        }
    }
}

/// Applies the chosen interface language immediately by swapping the bundle used
/// for string lookups, then nudging the whole view tree to re-render.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: InterfaceLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "interfaceLanguage")
        let lang = raw.flatMap(InterfaceLanguage.init(rawValue:)) ?? .system
        language = lang
        Bundle.setAppLanguage(lang.lproj)
    }

    func set(_ lang: InterfaceLanguage) {
        guard lang != language else { return }
        UserDefaults.standard.set(lang.rawValue, forKey: "interfaceLanguage")
        Bundle.setAppLanguage(lang.lproj)
        // Keep AppleLanguages in sync so App Intents / system dialogs match too.
        if let id = lang.lproj {
            UserDefaults.standard.set([id], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        language = lang // published last → triggers the root's .id() re-render
    }
}

// MARK: - Runtime bundle language swap

nonisolated(unsafe) private var kLangBundleKey: UInt8 = 0

/// Bundle.main is reclassed to this so string lookups can be redirected to a
/// specific `.lproj`. For French (the source language there's no fr.lproj) the
/// associated bundle is nil, so `super` returns the key — which *is* the French
/// string. English loads en.lproj; system falls through to normal resolution.
final class AppLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let inner = objc_getAssociatedObject(self, &kLangBundleKey) as? Bundle {
            return inner.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    nonisolated(unsafe) private static var languageSwizzled = false

    static func setAppLanguage(_ lproj: String?) {
        if !languageSwizzled {
            object_setClass(Bundle.main, AppLanguageBundle.self)
            languageSwizzled = true
        }
        let inner: Bundle? = lproj.flatMap { name in
            Bundle.main.path(forResource: name, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        objc_setAssociatedObject(Bundle.main, &kLangBundleKey, inner, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Segmented Système / Français / English picker — switches the UI live.
struct LanguagePicker: View {
    @ObservedObject private var loc = LocalizationManager.shared
    var body: some View {
        Picker("", selection: Binding(get: { loc.language }, set: { loc.set($0) })) {
            ForEach(InterfaceLanguage.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}
