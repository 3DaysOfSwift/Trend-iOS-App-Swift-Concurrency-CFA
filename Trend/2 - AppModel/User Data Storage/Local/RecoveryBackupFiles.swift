// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation

protocol RecoveryBackupProviding: Sendable {
    func prepareBackupIfNeeded(_ snapshot: RecoverySnapshot, force: Bool) async throws -> URL
    func uploadPreparedBackup(_ localURL: URL) async throws -> Bool
    func preview(_ url: URL) async throws -> RecoverySnapshot
}

/// Backup documents only. This type cannot write to the live database.
actor RecoveryBackupFiles: RecoveryBackupProviding {
    private let access: any BackupFileAccess
    private let folder: URL
    private let cloudFolder: @Sendable () -> URL?
    private let now: @Sendable () -> Date
    private let interval: TimeInterval
    private let automaticInterval: TimeInterval

    init(folder: URL, access: any BackupFileAccess = CoordinatedBackupFileAccess(), interval: TimeInterval = 7 * 24 * 60 * 60,
         automaticInterval: TimeInterval = 24 * 60 * 60,
         now: @escaping @Sendable () -> Date = { .now },
         cloudFolder: @escaping @Sendable () -> URL? = {
             FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(path: "Documents", directoryHint: .isDirectory)
         }) {
        self.access = access
        self.folder = folder
        self.interval = interval
        self.automaticInterval = automaticInterval
        self.now = now
        self.cloudFolder = cloudFolder
    }

    /// Check on every trigger, but create at most one automatic snapshot per
    /// 24 hours. Manual backup bypasses the interval. Retrying an existing file
    /// does not create another archive or reset the clock.
    func prepareBackupIfNeeded(_ snapshot: RecoverySnapshot, force: Bool) throws -> URL {
        let latest = folder.appending(path: "Latest.json")
        if !force, FileManager.default.fileExists(atPath: latest.path) {
            let existing = try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: latest))
            try existing.validate()
            if now().timeIntervalSince(existing.createdAt) < automaticInterval { return latest }
        }
        return try saveLocal(snapshot)
    }

    func saveLocal(_ snapshot: RecoverySnapshot) throws -> URL {
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        try JSONDecoder().decode(RecoverySnapshot.self, from: data).validate()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let weekly = folder.appending(path: "Weekly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: weekly, withIntermediateDirectories: true)
        let retained = try FileManager.default.contentsOfDirectory(at: weekly, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let lastDate = try retained.map { try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: $0)).createdAt }.max()
        if lastDate == nil || now().timeIntervalSince(lastDate!) >= interval {
            try data.write(to: weekly.appending(path: "\(Int(now().timeIntervalSince1970))-\(snapshot.revision).json"), options: .atomic)
        }
        let latest = folder.appending(path: "Latest.json")
        // The prior latest remains available even when a new snapshot records a deletion.
        if FileManager.default.fileExists(atPath: latest.path) {
            let previous = try Data(contentsOf: latest)
            let previousSnapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: previous)
            try previousSnapshot.validate()
            if previousSnapshot.revision == snapshot.revision &&
                previousSnapshot.weightUnit == snapshot.weightUnit &&
                previousSnapshot.appVersion == snapshot.appVersion &&
                previousSnapshot.appBuild == snapshot.appBuild { return latest }
            try previous.write(to: folder.appending(path: "Previous.json"), options: .atomic)
        }
        try data.write(to: latest, options: .atomic)
        return latest
    }

    func uploadPreparedBackup(_ localURL: URL) throws -> Bool {
        let snapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: localURL))
        return try upload(localURL, revision: snapshot.revision)
    }

    func upload(_ localURL: URL, revision: String) throws -> Bool {
        guard let cloud = cloudFolder() else { throw StoreError.failure("Saved on this iPhone. iCloud Drive is unavailable; backup will retry when the app is active.") }
        if let token = FileManager.default.ubiquityIdentityToken {
            try BackupCloudAccount.verify(token, in: folder)
        }
        // Each installation owns its recovery files. A new phone downloading
        // only part of its CloudKit history cannot overwrite the old phone's backup.
        let identityFile = folder.appending(path: "Installation.txt")
        let identity: String
        if FileManager.default.fileExists(atPath: identityFile.path) {
            identity = try String(contentsOf: identityFile, encoding: .utf8)
            guard UUID(uuidString: identity) != nil else { throw StoreError.failure("Invalid backup folder identity.") }
        } else {
            identity = UUID().uuidString
            try Data(identity.utf8).write(to: identityFile, options: .atomic)
        }
        let destination = cloud.appending(path: "Backups/\(identity)", directoryHint: .isDirectory)
        let weeklyDestination = destination.appending(path: "Weekly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: weeklyDestination, withIntermediateDirectories: true)
        let data = try Data(contentsOf: localURL)
        let snapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: data)
        try snapshot.validate()
        guard snapshot.revision == revision else { throw StoreError.failure("Backup revision changed. Please try again.") }
        let weekly = try FileManager.default.contentsOfDirectory(at: folder.appending(path: "Weekly"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var targets: [URL] = []
        for source in weekly {
            let bytes = try Data(contentsOf: source)
            try JSONDecoder().decode(RecoverySnapshot.self, from: bytes).validate()
            let target = weeklyDestination.appending(path: source.lastPathComponent)
            try access.writeNewSnapshot(bytes, to: target)
            targets.append(target)
        }
        let previous = folder.appending(path: "Previous.json")
        if FileManager.default.fileExists(atPath: previous.path) {
            let bytes = try Data(contentsOf: previous)
            try JSONDecoder().decode(RecoverySnapshot.self, from: bytes).validate()
            let target = destination.appending(path: "Previous.json")
            try access.replaceSnapshot(bytes, at: target)
            targets.append(target)
        }
        let target = destination.appending(path: "Latest.json")
        try access.replaceSnapshot(data, at: target)
        targets.append(target)
        return try targets.allSatisfy {
            try $0.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]).ubiquitousItemIsUploaded == true
        }
    }

    func preview(_ url: URL) throws -> RecoverySnapshot {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let data = try access.read(url)
        let snapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }
}

/// Never silently send retained recovery files to a different iCloud account.
/// Signing back into the original account allows retries without losing files.
enum BackupCloudAccount {
    static func verify(_ token: any NSObjectProtocol & NSCoding, in folder: URL) throws {
        let file = folder.appending(path: "CloudAccount.archive")
        if FileManager.default.fileExists(atPath: file.path) {
            let reader = try NSKeyedUnarchiver(forReadingFrom: Data(contentsOf: file))
            reader.requiresSecureCoding = false
            defer { reader.finishDecoding() }
            guard let previous = reader.decodeObject(forKey: NSKeyedArchiveRootObjectKey),
                  token.isEqual(previous) else {
                throw StoreError.failure("The iCloud account changed. Recovery uploads are paused to protect the previous account’s backups. Sign back into the original account to resume.")
            }
        } else {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
            try data.write(to: file, options: .atomic)
        }
    }
}

protocol BackupFileAccess: Sendable {
    func writeNewSnapshot(_ data: Data, to target: URL) throws
    func replaceSnapshot(_ data: Data, at target: URL) throws
    func read(_ url: URL) throws -> Data
}

/// The operating-system boundary, replaceable by a local file double in unit tests.
struct CoordinatedBackupFileAccess: BackupFileAccess {
    func replaceSnapshot(_ data: Data, at target: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path), try Data(contentsOf: url) == data { return }
                try data.write(to: url, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
    }
    func writeNewSnapshot(_ data: Data, to target: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                // Immutable, unique snapshots: a fresh installation never overwrites a previous backup.
                if FileManager.default.fileExists(atPath: url.path) {
                    guard try Data(contentsOf: url) == data else {
                        throw StoreError.failure("An existing backup differs from this snapshot. It has been preserved, not overwritten.")
                    }
                } else { try data.write(to: url, options: .atomic) }
            } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }

    }
    func read(_ url: URL) throws -> Data {
        var data: Data?
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            do { data = try Data(contentsOf: location) } catch { readError = error }
        }
        if let error = coordinationError ?? readError as NSError? { throw error }
        guard let data else { throw StoreError.failure("The backup has not downloaded yet. Please try again.") }

        return data
    }
}
