import SwiftUI

/// Bring-your-own-key setup. Both keys are stored in the Keychain (ClaudeKit's
/// `KeychainStore`) — the Atelier (Claude) and table-read (ElevenLabs) surfaces
/// unlock once their key is present.
struct KeySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var claude = ""
    @State private var eleven = ""
    @State private var claudeSet = AppKeys.hasAnthropic
    @State private var elevenSet = AppKeys.hasElevenLabs

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FieldGroup("L'Atelier — écriture assistée") {
                        keyField(text: $claude, isSet: claudeSet, hint: "console.anthropic.com → API keys")
                    }
                    FieldGroup("Lecture à voix — voix ElevenLabs") {
                        keyField(text: $eleven, isSet: elevenSet, hint: "elevenlabs.io → Profile → API key")
                    }
                    Text("Tes clés restent sur cet appareil, dans le trousseau. Elles ne quittent jamais l'app.")
                        .font(.footnote).foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.deskLight)
            .navigationTitle("Clés")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save(); dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 400)
        #endif
    }

    @ViewBuilder
    private func keyField(text: Binding<String>, isSet: Bool, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSet {
                Label("Enregistrée", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(Theme.jade)
            }
            SecureField(isSet ? "•••••••• (remplacer)" : "Colle ta clé…", text: text)
                .sheetField()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            Text(hint).font(.caption).foregroundStyle(Theme.inkFaint)
        }
    }

    private func save() {
        let c = claude.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { _ = AppKeys.anthropic.save(c) }
        let e = eleven.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { _ = AppKeys.elevenLabs.save(e) }
    }
}
