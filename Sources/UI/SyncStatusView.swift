import SwiftUI
import CloudKit

/// Is this device actually syncing?
///
/// `Persistence` falls back from CloudKit → local → memory when the store can't
/// open, and until now it did so **silently**: a device that quietly stopped
/// syncing looked identical to one that was working, and the only symptom was
/// libraries drifting apart with no explanation. This surfaces the truth.
@MainActor
final class SyncStatus: ObservableObject {
    @Published private(set) var accountLabel: String = "…"
    @Published private(set) var accountOK = false

    func refresh() async {
        do {
            let status = try await CKContainer(identifier: "iCloud.app.atelier.lareplique").accountStatus()
            switch status {
            case .available:
                accountLabel = String(localized: "Compte iCloud actif"); accountOK = true
            case .noAccount:
                accountLabel = String(localized: "Aucun compte iCloud sur cet appareil"); accountOK = false
            case .restricted:
                accountLabel = String(localized: "iCloud restreint sur cet appareil"); accountOK = false
            case .couldNotDetermine:
                accountLabel = String(localized: "État iCloud indéterminé"); accountOK = false
            case .temporarilyUnavailable:
                accountLabel = String(localized: "iCloud temporairement indisponible"); accountOK = false
            @unknown default:
                accountLabel = String(localized: "État iCloud inconnu"); accountOK = false
            }
        } catch {
            accountLabel = error.localizedDescription
            accountOK = false
        }
    }
}

/// Two plain rows — where the plays are stored, and whether iCloud is reachable.
struct SyncStatusRows: View {
    @StateObject private var status = SyncStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: tierLabel, ok: Persistence.tier == .cloudKit, icon: tierIcon)
            row(label: status.accountLabel, ok: status.accountOK,
                icon: status.accountOK ? "person.icloud.fill" : "exclamationmark.icloud.fill")

            if Persistence.tier != .cloudKit {
                Text("Cet appareil ne synchronise pas — tes pièces restent ici. Vérifie que tu es connecté à iCloud, puis relance l'app.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(label: String, ok: Bool, icon: String) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon).foregroundStyle(ok ? Color.green : Theme.amber)
        }
        .font(.callout)
        .task { await status.refresh() }
    }

    private var tierLabel: String {
        switch Persistence.tier {
        case .cloudKit: return String(localized: "Synchronisé par iCloud")
        case .local: return String(localized: "Local — pas de synchronisation")
        case .memory: return String(localized: "Mémoire seulement — rien n'est conservé")
        }
    }

    private var tierIcon: String {
        switch Persistence.tier {
        case .cloudKit: return "checkmark.icloud.fill"
        case .local: return "internaldrive.fill"
        case .memory: return "exclamationmark.triangle.fill"
        }
    }
}
