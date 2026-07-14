import Foundation
import CloudKit
import SwiftData

/// Publishes a play as a read-only public record so anyone with the link can
/// read it on the web viewer (`/lire/:id`). Writes a `PublicPlay` record whose
/// `recordName` is the shareID into the container's PUBLIC database, holding the
/// portable `la-replique/1` JSON string. Re-publishing updates in place;
/// dépublier deletes the record.
enum Publish {
    static let recordType = "PublicPlay"
    static let containerID = "iCloud.app.atelier.lareplique"
    static let webBase = "https://la-replique.netlify.app/lire/"

    private static var container: CKContainer { CKContainer(identifier: containerID) }

    enum PublishError: LocalizedError {
        case notSignedIn
        case encoding
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return String(localized: "Connecte-toi à iCloud pour publier une lecture.")
            case .encoding: return String(localized: "La pièce n'a pas pu être encodée.")
            case .failed(let m): return m
            }
        }
    }

    /// The public web URL for a shareID.
    static func webURL(for shareID: String) -> URL {
        URL(string: webBase + shareID)!
    }

    /// Publish (or re-publish) a play. Returns its shareID.
    @MainActor
    @discardableResult
    static func publish(_ play: Play, context: ModelContext) async throws -> String {
        try await ensureSignedIn()

        let data = try PlayFormat.aiJSON(from: play)
        guard let jsonString = String(data: data, encoding: .utf8) else { throw PublishError.encoding }

        let shareID = play.publicShareID ?? newShareID()
        let recordID = CKRecord.ID(recordName: shareID)
        let db = container.publicCloudDatabase

        // Fetch-or-create so re-publishing an already-shared play updates in place.
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
        } catch let e as CKError where e.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["json"] = jsonString as CKRecordValue
        record["title"] = play.title as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        do {
            _ = try await db.save(record)
        } catch let e as CKError {
            throw PublishError.failed(friendly(e))
        }

        play.publicShareID = shareID
        play.touch()
        try? context.save()
        return shareID
    }

    /// Remove a play's public record. Safe to call when already unpublished.
    @MainActor
    static func unpublish(_ play: Play, context: ModelContext) async throws {
        guard let shareID = play.publicShareID else { return }
        let db = container.publicCloudDatabase
        do {
            _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: shareID))
        } catch let e as CKError where e.code == .unknownItem {
            // Already gone on the server — treat as success.
        } catch let e as CKError {
            throw PublishError.failed(friendly(e))
        }
        play.publicShareID = nil
        play.touch()
        try? context.save()
    }

    // MARK: - Helpers

    @MainActor
    private static func ensureSignedIn() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw PublishError.notSignedIn }
    }

    /// A short, URL-safe, unguessable share id (base64url of 12 random bytes).
    static func newShareID() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func friendly(_ e: CKError) -> String {
        switch e.code {
        case .networkUnavailable, .networkFailure:
            return String(localized: "Pas de connexion réseau.")
        case .notAuthenticated:
            return String(localized: "Connecte-toi à iCloud pour publier une lecture.")
        case .quotaExceeded:
            return String(localized: "Quota iCloud dépassé.")
        case .permissionFailure:
            return String(localized: "Permission iCloud refusée.")
        default:
            return e.localizedDescription
        }
    }
}
