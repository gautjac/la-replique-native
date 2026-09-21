import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Firebase, configured once. Two modes:
///  • the real project — when `GoogleService-Info.plist` is in the bundle;
///  • the local emulator — DEBUG, `LR_COLLAB_EMULATOR=1` (Firestore 127.0.0.1:8085,
///    Auth :9099, demo project, anonymous sign-in). This is how two simulators
///    edit one play on a developer Mac with no cloud project at all.
/// With neither, writing together is simply not offered.
@MainActor
enum CollabBackend {
    enum Mode { case unavailable, emulator, live }
    private(set) static var mode: Mode = .unavailable
    private static var configured = false

    static var isAvailable: Bool { configure(); return mode != .unavailable }

    static func configure() {
        guard !configured else { return }
        configured = true
        let env = ProcessInfo.processInfo.environment
        guard env["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        if env["LR_COLLAB_EMULATOR"] == "1" {
            let o = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef", gcmSenderID: "1234567890")
            o.projectID = "demo-la-replique"
            o.apiKey = "AIza" + String(repeating: "0", count: 35)
            FirebaseApp.configure(options: o)
            let host = env["LR_COLLAB_HOST"] ?? "127.0.0.1"
            let s = Firestore.firestore().settings
            s.host = "\(host):8085"; s.isSSLEnabled = false
            s.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = s
            Auth.auth().useEmulator(withHost: host, port: 9099)
            mode = .emulator
            return
        }
        #endif
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            mode = .live
        }
    }

    static var db: Firestore { Firestore.firestore() }
    static var uid: String? { Auth.auth().currentUser?.uid }

    /// The signed-in person's uid. On the emulator that is an anonymous account;
    /// the real project signs in with Apple / Google / an email link (step 2).
    static func ensureSignedIn() async throws -> String {
        configure()
        if let uid { return uid }
        guard mode == .emulator else { throw CollabError.notSignedIn }
        return try await Auth.auth().signInAnonymously().user.uid
    }
}

enum CollabError: LocalizedError {
    case unavailable, notSignedIn, badInvite, expiredInvite, notFound, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "L'écriture à plusieurs n'est pas encore disponible dans cette version.")
        case .notSignedIn: return String(localized: "Connecte-toi pour écrire à plusieurs.")
        case .badInvite: return String(localized: "Cette invitation n'existe pas. Vérifie le code.")
        case .expiredInvite: return String(localized: "Cette invitation a expiré. Demandes-en une nouvelle.")
        case .notFound: return String(localized: "Cette pièce n'est plus partagée.")
        case .failed(let m): return m
        }
    }
}
