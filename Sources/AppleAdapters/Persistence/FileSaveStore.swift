import Foundation
import GameApplication

/// JSON files under Application Support (plan §16.1: `campaign_progress.json`,
/// `suspended_session.json`; every file carries `schemaVersion`, writes are
/// atomic). The version is read FIRST and gated before the document is
/// decoded, so a file from a later build or a corrupt one is reported as an
/// error, never trapped on; callers treat an unreadable file as absent and
/// keep the file for inspection.
public final class FileSaveStore: CampaignPersistence {
    public enum FileError: Error { case unreadable(String), notAnObject(String) }

    public let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// The app's store: `<Application Support>/SparkTread/`.
    public static func standard() throws -> FileSaveStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try FileSaveStore(directory: base.appendingPathComponent("SparkTread", isDirectory: true))
    }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var progressURL: URL { directory.appendingPathComponent("campaign_progress.json") }
    public var suspendedURL: URL { directory.appendingPathComponent("suspended_session.json") }

    public func loadProgress() throws -> CampaignProgress? {
        guard let document: CampaignProgress = try read(progressURL) else { return nil }
        let issues = document.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        return document
    }

    public func saveProgress(_ progress: CampaignProgress) throws {
        let issues = progress.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        try write(progress, to: progressURL)
    }

    public func loadSuspended() throws -> SuspendedSession? {
        guard let document: SuspendedSession = try read(suspendedURL) else { return nil }
        let issues = document.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        return document
    }

    public func saveSuspended(_ session: SuspendedSession) throws {
        let issues = session.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        try write(session, to: suspendedURL)
    }

    public func clearSuspended() throws {
        if FileManager.default.fileExists(atPath: suspendedURL.path) {
            try FileManager.default.removeItem(at: suspendedURL)
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// nil when the file does not exist; version-gated before decoding.
    private func read<T: Decodable>(_ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw FileError.unreadable(url.lastPathComponent) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FileError.notAnObject(url.lastPathComponent)
        }
        try SaveSchema.check(version: object["schemaVersion"] as? Int ?? -1)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
