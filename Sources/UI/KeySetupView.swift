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
            Form {
                Section {
                    keyField("Clé Anthropic (Claude)", text: $claude, isSet: claudeSet,
                             hint: "console.anthropic.com → API keys")
                } header: { Text("L'Atelier — écriture assistée") }

                Section {
                    keyField("Clé ElevenLabs", text: $eleven, isSet: elevenSet,
                             hint: "elevenlabs.io → Profile → API key")
                } header: { Text("Lecture à voix — voix ElevenLabs") }
                footer: {
                    Text("Tes clés restent sur cet appareil, dans le trousseau. Elles ne quittent jamais l'app.")
                }
            }
            .navigationTitle("Clés")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 360)
        #endif
    }

    @ViewBuilder
    private func keyField(_ title: String, text: Binding<String>, isSet: Bool, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                if isSet {
                    Label("Enregistrée", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(Theme.jade).labelStyle(.titleAndIcon)
                }
            }
            SecureField(isSet ? "•••••••• (remplacer)" : "Colle ta clé…", text: text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let c = claude.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { _ = AppKeys.anthropic.save(c) }
        let e = eleven.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { _ = AppKeys.elevenLabs.save(e) }
    }
}
