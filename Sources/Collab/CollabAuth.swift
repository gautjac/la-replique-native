import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

/// Who is writing. Three ways in — Apple, Google, an emailed link — because the
/// people around a play are not all on Apple devices.
@MainActor
final class CollabAuth: ObservableObject {
    static let shared = CollabAuth()

    struct Person: Equatable {
        var uid: String
        var name: String
        var email: String?
        var isAnonymous: Bool
    }

    @Published private(set) var person: Person?
    /// An email a sign-in link was sent to, waiting for the link to come back.
    @AppStorage("collab.pendingEmail") var pendingEmail = ""

    private var appleNonce: String?
    private var handle: AuthStateDidChangeListenerHandle?

    static let continueURL = "https://la-replique.netlify.app/connexion"

    private init() {
        guard CollabBackend.isAvailable else { return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated {
                self?.person = user.map {
                    Person(uid: $0.uid, name: $0.displayName ?? "", email: $0.email, isAnonymous: $0.isAnonymous)
                }
            }
        }
    }

    var isSignedIn: Bool { person != nil }

    // MARK: Apple

    /// Call from `SignInWithAppleButton`'s request closure.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Call from `SignInWithAppleButton`'s completion closure.
    func finishApple(_ result: Result<ASAuthorization, Error>) async throws {
        let auth = try result.get()
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let nonce = appleNonce else { throw CollabError.failed(String(localized: "Apple n'a pas renvoyé d'identité.")) }
        let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: cred.fullName)
        let user = try await Auth.auth().signIn(with: credential).user
        // Apple gives the name ONCE, on the first authorisation — keep it.
        if (user.displayName ?? "").isEmpty, let n = cred.fullName {
            let name = PersonNameComponentsFormatter().string(from: n)
            if !name.isEmpty { try? await rename(name) }
        }
    }

    // MARK: Google

    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw CollabError.failed(String(localized: "La connexion Google n'est pas configurée."))
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        #if os(iOS)
        guard let presenter = Self.topViewController() else { throw CollabError.unavailable }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        #else
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { throw CollabError.unavailable }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        #endif
        guard let idToken = result.user.idToken?.tokenString else {
            throw CollabError.failed(String(localized: "Google n'a pas renvoyé d'identité."))
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        _ = try await Auth.auth().signIn(with: credential)
    }

    /// Route the Google redirect back into the SDK (`.onOpenURL`).
    @discardableResult
    func handle(_ url: URL) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) { return true }
        if Auth.auth().isSignIn(withEmailLink: url.absoluteString) {
            Task { try? await finishEmail(link: url.absoluteString) }
            return true
        }
        return false
    }

    // MARK: Email link

    func sendLink(to raw: String) async throws {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let settings = ActionCodeSettings()
        settings.url = URL(string: Self.continueURL)
        settings.handleCodeInApp = true
        try await Auth.auth().sendSignInLink(toEmail: email, actionCodeSettings: settings)
        pendingEmail = email
    }

    /// The link from the email — opened on this device, or pasted in (the page it
    /// lands on offers "copy this link": that is how it works on a Mac, and on a
    /// phone whose mail opens in another browser).
    func finishEmail(link raw: String) async throws {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Auth.auth().isSignIn(withEmailLink: link) else {
            throw CollabError.failed(String(localized: "Ce n'est pas un lien de connexion. Copie le lien complet reçu par courriel."))
        }
        guard !pendingEmail.isEmpty else {
            throw CollabError.failed(String(localized: "Écris d'abord ton courriel, puis demande un lien."))
        }
        _ = try await Auth.auth().signIn(withEmail: pendingEmail, link: link)
        pendingEmail = ""
    }

    // MARK: account

    func rename(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try await change.commitChanges()
        person?.name = name
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    // MARK: helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    #if os(iOS)
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
    #endif
}

// MARK: - Sign-in panel

/// The three ways in. Embedded wherever writing together needs to know who you are.
struct CollabSignInView: View {
    @ObservedObject private var auth = CollabAuth.shared
    @State private var email = ""
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Dis-nous qui tu es", systemImage: "person.crop.circle").font(.headline).foregroundStyle(.white)
            Text("Pour écrire à plusieurs, chacun signe ses changements et ses notes. Choisis la façon qui te convient.")
                .foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.continue) { auth.prepare($0) } onCompletion: { result in
                run { try await auth.finishApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { run { try await auth.signInWithGoogle() } } label: {
                HStack(spacing: 8) {
                    Text("G").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("Continuer avec Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Theme.desk, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.rule))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            FieldGroup("Ou par courriel — sans mot de passe") {
                HStack(spacing: 8) {
                    TextField("toi@exemple.ca", text: $email).sheetField()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                        #endif
                    Button("Envoyer le lien") { run { try await auth.sendLink(to: email); sent = true } }
                        .buttonStyle(.bordered).disabled(!email.contains("@") || busy)
                }
                if sent || !auth.pendingEmail.isEmpty {
                    Text("Lien envoyé à \(auth.pendingEmail). Ouvre-le sur cet appareil — ou copie-le et colle-le ici.")
                        .font(.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("Colle le lien reçu", text: $link).sheetField()
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                        Button("Me connecter") { run { try await auth.finishEmail(link: link) } }
                            .buttonStyle(.borderedProminent).disabled(link.count < 20 || busy)
                    }
                }
            }

            if busy { ProgressView().controlSize(.small) }
            if let error {
                Text(error).font(.callout).foregroundStyle(Theme.rose)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task { @MainActor in
            do { try await op() }
            catch let e as NSError where e.domain == ASAuthorizationError.errorDomain && e.code == ASAuthorizationError.canceled.rawValue { /* closed the sheet: not an error */ }
            catch let e as NSError where e.domain == kGIDSignInErrorDomain && e.code == GIDSignInError.canceled.rawValue { }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// Réglages ▸ the account used for writing together.
struct CollabAccountRows: View {
    @ObservedObject private var auth = CollabAuth.shared
    var body: some View {
        if let p = auth.person {
            VStack(alignment: .leading, spacing: 8) {
                Label(p.email ?? (p.name.isEmpty ? String(localized: "Connecté·e") : p.name), systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.white)
                Button("Se déconnecter", role: .destructive) { auth.signOut() }.buttonStyle(.bordered).controlSize(.small)
            }
        } else {
            Text("Pas connecté·e. La connexion se fait au moment de partager ou de rejoindre une pièce.")
                .font(.callout).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
