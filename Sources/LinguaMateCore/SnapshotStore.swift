import Foundation

public enum PersistenceError: Error, LocalizedError {
    case unsupportedVersion(Int), unreadable
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "数据版本 \(version) 不受当前 App 支持。请更新 App，原文件未被覆盖。"
        case .unreadable: return "学习数据无法读取。原文件已保留，可先导出备份，再尝试恢复。"
        }
    }
}

public struct SnapshotStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let version: Int
        do { version = try decoder.decode(Header.self, from: data).schemaVersion }
        catch { throw PersistenceError.unreadable }
        guard version == AppSnapshot.currentVersion else { throw PersistenceError.unsupportedVersion(version) }
        do { return try decoder.decode(AppSnapshot.self, from: data) }
        catch { throw PersistenceError.unreadable }
    }

    public func save(_ snapshot: AppSnapshot) throws {
        guard snapshot.schemaVersion == AppSnapshot.currentVersion else { throw PersistenceError.unsupportedVersion(snapshot.schemaVersion) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    @discardableResult
    public func preserveBackup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let backup = url.deletingLastPathComponent().appendingPathComponent("learning-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }

    public func removeRecoveryBackups() throws {
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix("learning-backup-") && file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }
}
