import Foundation
import GRDB
import OSLog

/// Database service for managing sync state and metadata
/// Uses GRDB.swift for SQLite database operations
class DatabaseService {
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "Database")

    // MARK: - Database Schema Version

    private static let currentSchemaVersion = 5

    // MARK: - Initialization

    init(databaseURL: URL? = nil) throws {
        let dbURL: URL
        if let url = databaseURL {
            dbURL = url
        } else {
            // Default location: Application Support
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appFolder = appSupport.appendingPathComponent("iCloudPhotosBackup", isDirectory: true)

            if !FileManager.default.fileExists(atPath: appFolder.path) {
                try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }

            dbURL = appFolder.appendingPathComponent("sync.db")
        }

        logger.info("Initializing database at: \(dbURL.path)")

        do {
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try createTablesIfNeeded()
            try migrateIfNeeded()
            logger.info("Database initialized successfully")
        } catch {
            logger.error("Database initialization failed: \(error.localizedDescription)")
            throw DatabaseError.initializationFailed(underlying: error)
        }
    }

    // MARK: - Schema Creation

    private func createTablesIfNeeded() throws {
        try dbQueue.write { db in
            // Schema version table
            try db.create(table: "schema_version", ifNotExists: true) { t in
                t.column("version", .integer).notNull()
                t.column("applied_at", .datetime).notNull()
            }

            // Synced photos table
            try db.create(table: "synced_photos", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("local_id", .text).notNull()
                t.column("remote_path", .text).notNull()
                t.column("destination_id", .text).notNull()
                t.column("checksum", .text).notNull()
                t.column("sync_date", .datetime).notNull()
                t.column("file_size", .integer).notNull()
                t.column("last_verified_date", .datetime)
                t.column("file_metadata", .blob)
            }

            // Indices for synced_photos
            try db.create(index: "idx_synced_photos_destination", on: "synced_photos", columns: ["destination_id"], ifNotExists: true)
            try db.create(index: "idx_synced_photos_checksum", on: "synced_photos", columns: ["checksum"], ifNotExists: true)
            try db.create(index: "idx_synced_photos_local_id", on: "synced_photos", columns: ["local_id"], ifNotExists: true)
            try db.create(index: "idx_synced_photos_verified", on: "synced_photos", columns: ["last_verified_date"], ifNotExists: true)

            // Sync jobs table
            try db.create(table: "sync_jobs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("destination_id", .text).notNull()
                t.column("status", .text).notNull()
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
                t.column("photos_scanned", .integer).notNull().defaults(to: 0)
                t.column("photos_synced", .integer).notNull().defaults(to: 0)
                t.column("photos_failed", .integer).notNull().defaults(to: 0)
                t.column("bytes_transferred", .integer).notNull().defaults(to: 0)
                t.column("average_speed", .double)
            }

            try db.create(index: "idx_sync_jobs_destination", on: "sync_jobs", columns: ["destination_id"], ifNotExists: true)
            try db.create(index: "idx_sync_jobs_start_time", on: "sync_jobs", columns: ["start_time"], ifNotExists: true)

            // Sync errors table
            try db.create(table: "sync_errors", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("job_id", .text).notNull()
                t.column("photo_id", .text).notNull()
                t.column("error_message", .text).notNull()
                t.column("error_category", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("retry_count", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_sync_errors_job", on: "sync_errors", columns: ["job_id"], ifNotExists: true)

            // Destinations table
            try db.create(table: "destinations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("config_json", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("last_health_check", .datetime)
                t.column("health_status", .text).notNull().defaults(to: "unknown")
            }

            // Deleted photos table
            try db.create(table: "deleted_photos", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("local_id", .text).notNull()
                t.column("deletion_date", .datetime).notNull()
                t.column("destination_id", .text).notNull()
                t.column("remote_path", .text).notNull()
            }

            try db.create(index: "idx_deleted_photos_destination", on: "deleted_photos", columns: ["destination_id"], ifNotExists: true)

            // Verification jobs table
            try db.create(table: "verification_jobs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("destination_id", .text).notNull()
                t.column("type", .text).notNull()
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
                t.column("total_photos", .integer).notNull().defaults(to: 0)
                t.column("verified_count", .integer).notNull().defaults(to: 0)
                t.column("mismatch_count", .integer).notNull().defaults(to: 0)
                t.column("missing_count", .integer).notNull().defaults(to: 0)
                t.column("error_count", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_verification_jobs_destination", on: "verification_jobs", columns: ["destination_id"], ifNotExists: true)
            try db.create(index: "idx_verification_jobs_start_time", on: "verification_jobs", columns: ["start_time"], ifNotExists: true)

            // Scheduled backup jobs table
            try db.create(table: "scheduled_backup_jobs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("destination_id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("is_enabled", .boolean).notNull().defaults(to: true)
                t.column("schedule_type_json", .blob).notNull()
                t.column("filter", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("last_run_time", .datetime)
                t.column("next_run_time", .datetime)
                t.column("last_run_status", .text)
            }

            try db.create(index: "idx_scheduled_jobs_destination", on: "scheduled_backup_jobs", columns: ["destination_id"], ifNotExists: true)
            try db.create(index: "idx_scheduled_jobs_next_run", on: "scheduled_backup_jobs", columns: ["next_run_time"], ifNotExists: true)
            try db.create(index: "idx_scheduled_jobs_enabled", on: "scheduled_backup_jobs", columns: ["is_enabled"], ifNotExists: true)

            // Sync logs table
            try db.create(table: "sync_logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("job_id", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("level", .text).notNull()
                t.column("category", .text).notNull()
                t.column("message", .text).notNull()
                t.column("photo_id", .text)
                t.column("details", .text)
            }

            try db.create(index: "idx_sync_logs_job_id", on: "sync_logs", columns: ["job_id"], ifNotExists: true)
            try db.create(index: "idx_sync_logs_timestamp", on: "sync_logs", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_sync_logs_level", on: "sync_logs", columns: ["level"], ifNotExists: true)

            // Verification logs table
            try db.create(table: "verification_logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("job_id", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("level", .text).notNull()
                t.column("category", .text).notNull()
                t.column("message", .text).notNull()
                t.column("photo_path", .text)
                t.column("details", .text)
            }

            try db.create(index: "idx_verification_logs_job_id", on: "verification_logs", columns: ["job_id"], ifNotExists: true)
            try db.create(index: "idx_verification_logs_timestamp", on: "verification_logs", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_verification_logs_level", on: "verification_logs", columns: ["level"], ifNotExists: true)

            logger.info("Database tables created")
        }
    }

    // MARK: - Migrations

    private func migrateIfNeeded() throws {
        try dbQueue.write { db in
            let currentVersion = try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_version") ?? 0

            if currentVersion < Self.currentSchemaVersion {
                logger.info("Migrating database from version \(currentVersion) to \(Self.currentSchemaVersion)")

                // Migration from version 1 to 2: Add verification_jobs table
                if currentVersion < 2 && currentVersion >= 1 {
                    // Check if table exists (for fresh installs it will be created in createTablesIfNeeded)
                    let tableExists = try Bool.fetchOne(db, sql: """
                        SELECT COUNT(*) > 0 FROM sqlite_master
                        WHERE type='table' AND name='verification_jobs'
                    """) ?? false

                    if !tableExists {
                        try db.execute(sql: """
                            CREATE TABLE verification_jobs (
                                id TEXT PRIMARY KEY,
                                destination_id TEXT NOT NULL,
                                type TEXT NOT NULL,
                                start_time DATETIME NOT NULL,
                                end_time DATETIME,
                                total_photos INTEGER NOT NULL DEFAULT 0,
                                verified_count INTEGER NOT NULL DEFAULT 0,
                                mismatch_count INTEGER NOT NULL DEFAULT 0,
                                missing_count INTEGER NOT NULL DEFAULT 0,
                                error_count INTEGER NOT NULL DEFAULT 0
                            )
                        """)

                        try db.execute(sql: "CREATE INDEX idx_verification_jobs_destination ON verification_jobs(destination_id)")
                        try db.execute(sql: "CREATE INDEX idx_verification_jobs_start_time ON verification_jobs(start_time)")

                        logger.info("Created verification_jobs table")
                    }
                }

                // Migration from version 2 to 3: Add scheduled_backup_jobs table
                if currentVersion < 3 && currentVersion >= 2 {
                    let tableExists = try Bool.fetchOne(db, sql: """
                        SELECT COUNT(*) > 0 FROM sqlite_master
                        WHERE type='table' AND name='scheduled_backup_jobs'
                    """) ?? false

                    if !tableExists {
                        try db.execute(sql: """
                            CREATE TABLE scheduled_backup_jobs (
                                id TEXT PRIMARY KEY,
                                destination_id TEXT NOT NULL,
                                name TEXT NOT NULL,
                                is_enabled INTEGER NOT NULL DEFAULT 1,
                                schedule_type_json BLOB NOT NULL,
                                filter TEXT NOT NULL,
                                created_at DATETIME NOT NULL,
                                last_run_time DATETIME,
                                next_run_time DATETIME,
                                last_run_status TEXT
                            )
                        """)

                        try db.execute(sql: "CREATE INDEX idx_scheduled_jobs_destination ON scheduled_backup_jobs(destination_id)")
                        try db.execute(sql: "CREATE INDEX idx_scheduled_jobs_next_run ON scheduled_backup_jobs(next_run_time)")
                        try db.execute(sql: "CREATE INDEX idx_scheduled_jobs_enabled ON scheduled_backup_jobs(is_enabled)")

                        logger.info("Created scheduled_backup_jobs table")
                    }
                }

                // Migration from version 3 to 4: Add sync_logs table
                if currentVersion < 4 && currentVersion >= 3 {
                    let tableExists = try Bool.fetchOne(db, sql: """
                        SELECT COUNT(*) > 0 FROM sqlite_master
                        WHERE type='table' AND name='sync_logs'
                    """) ?? false

                    if !tableExists {
                        try db.execute(sql: """
                            CREATE TABLE sync_logs (
                                id TEXT PRIMARY KEY,
                                job_id TEXT NOT NULL,
                                timestamp DATETIME NOT NULL,
                                level TEXT NOT NULL,
                                category TEXT NOT NULL,
                                message TEXT NOT NULL,
                                photo_id TEXT,
                                details TEXT
                            )
                        """)

                        try db.execute(sql: "CREATE INDEX idx_sync_logs_job_id ON sync_logs(job_id)")
                        try db.execute(sql: "CREATE INDEX idx_sync_logs_timestamp ON sync_logs(timestamp)")
                        try db.execute(sql: "CREATE INDEX idx_sync_logs_level ON sync_logs(level)")

                        logger.info("Created sync_logs table")
                    }
                }

                // Migration from version 4 to 5: Add verification_logs table
                if currentVersion < 5 && currentVersion >= 4 {
                    let tableExists = try Bool.fetchOne(db, sql: """
                        SELECT COUNT(*) > 0 FROM sqlite_master
                        WHERE type='table' AND name='verification_logs'
                    """) ?? false

                    if !tableExists {
                        try db.execute(sql: """
                            CREATE TABLE verification_logs (
                                id TEXT PRIMARY KEY,
                                job_id TEXT NOT NULL,
                                timestamp DATETIME NOT NULL,
                                level TEXT NOT NULL,
                                category TEXT NOT NULL,
                                message TEXT NOT NULL,
                                photo_path TEXT,
                                details TEXT
                            )
                        """)

                        try db.execute(sql: "CREATE INDEX idx_verification_logs_job_id ON verification_logs(job_id)")
                        try db.execute(sql: "CREATE INDEX idx_verification_logs_timestamp ON verification_logs(timestamp)")
                        try db.execute(sql: "CREATE INDEX idx_verification_logs_level ON verification_logs(level)")

                        logger.info("Created verification_logs table")
                    }
                }

                // Record the new version
                try db.execute(sql: """
                    INSERT INTO schema_version (version, applied_at)
                    VALUES (?, ?)
                """, arguments: [Self.currentSchemaVersion, Date()])

                logger.info("Database migration completed")
            }
        }
    }

    // MARK: - Synced Photos Operations

    func saveSyncedPhoto(_ photo: SyncedPhoto) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO synced_photos
                (id, local_id, remote_path, destination_id, checksum, sync_date, file_size, last_verified_date, file_metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                photo.id.uuidString,
                photo.localID,
                photo.remotePath,
                photo.destinationID.uuidString,
                photo.checksum,
                photo.syncDate,
                photo.fileSize,
                photo.lastVerifiedDate,
                photo.fileMetadata
            ])
        }
    }

    func getSyncedPhoto(localID: String, destinationID: UUID) throws -> SyncedPhoto? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM synced_photos
                WHERE local_id = ? AND destination_id = ?
            """, arguments: [localID, destinationID.uuidString]) else {
                return nil
            }

            return try parseSyncedPhoto(from: row)
        }
    }

    func getAllSyncedPhotos(destinationID: UUID) throws -> [SyncedPhoto] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM synced_photos
                WHERE destination_id = ?
                ORDER BY sync_date DESC
            """, arguments: [destinationID.uuidString])

            return try rows.map { try parseSyncedPhoto(from: $0) }
        }
    }

    func updateVerificationDate(photoID: UUID, date: Date) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE synced_photos
                SET last_verified_date = ?
                WHERE id = ?
            """, arguments: [date, photoID.uuidString])
        }
    }

    func deleteSyncedPhoto(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM synced_photos WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Batch Operations (Performance Optimized)

    /// Batch save multiple synced photos in a single transaction
    /// Much more efficient than individual saves for large imports
    func saveSyncedPhotosBatch(_ photos: [SyncedPhoto]) throws {
        try dbQueue.write { db in
            for photo in photos {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO synced_photos
                    (id, local_id, remote_path, destination_id, checksum, sync_date, file_size, last_verified_date, file_metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    photo.id.uuidString,
                    photo.localID,
                    photo.remotePath,
                    photo.destinationID.uuidString,
                    photo.checksum,
                    photo.syncDate,
                    photo.fileSize,
                    photo.lastVerifiedDate,
                    photo.fileMetadata
                ])
            }
        }
        logger.info("Batch saved \(photos.count) synced photos")
    }

    /// Check if multiple photos are already synced (batch deduplication)
    /// Returns a Set of local IDs that are already synced
    func getSyncedPhotoIDs(localIDs: [String], destinationID: UUID) throws -> Set<String> {
        guard !localIDs.isEmpty else { return [] }

        return try dbQueue.read { db in
            // Use chunking for very large sets to avoid SQLite limits
            let chunkSize = 500
            var syncedIDs = Set<String>()

            for chunk in localIDs.chunked(into: chunkSize) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                var arguments: [Any] = [destinationID.uuidString]
                arguments.append(contentsOf: chunk)

                let rows = try Row.fetchAll(db, sql: """
                    SELECT local_id FROM synced_photos
                    WHERE destination_id = ? AND local_id IN (\(placeholders))
                """, arguments: StatementArguments(arguments.map { $0 as! DatabaseValueConvertible })!)

                for row in rows {
                    if let localID: String = row["local_id"] {
                        syncedIDs.insert(localID)
                    }
                }
            }

            return syncedIDs
        }
    }

    /// Get synced photos with sync dates for modification detection
    /// Returns a dictionary of localID -> syncDate
    func getSyncedPhotosDates(localIDs: [String], destinationID: UUID) throws -> [String: Date] {
        guard !localIDs.isEmpty else { return [:] }

        return try dbQueue.read { db in
            let chunkSize = 500
            var result: [String: Date] = [:]

            for chunk in localIDs.chunked(into: chunkSize) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                var arguments: [Any] = [destinationID.uuidString]
                arguments.append(contentsOf: chunk)

                let rows = try Row.fetchAll(db, sql: """
                    SELECT local_id, sync_date FROM synced_photos
                    WHERE destination_id = ? AND local_id IN (\(placeholders))
                """, arguments: StatementArguments(arguments.map { $0 as! DatabaseValueConvertible })!)

                for row in rows {
                    if let localID: String = row["local_id"],
                       let syncDate: Date = row["sync_date"] {
                        result[localID] = syncDate
                    }
                }
            }

            return result
        }
    }

    /// Get full synced photo records for batch verification during deduplication
    /// Returns a dictionary mapping local_id to SyncedPhoto for quick lookup
    func getSyncedPhotosForVerification(localIDs: [String], destinationID: UUID) throws -> [String: SyncedPhoto] {
        guard !localIDs.isEmpty else { return [:] }

        return try dbQueue.read { db in
            let chunkSize = 500
            var result: [String: SyncedPhoto] = [:]

            for chunk in localIDs.chunked(into: chunkSize) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                var arguments: [Any] = [destinationID.uuidString]
                arguments.append(contentsOf: chunk)

                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM synced_photos
                    WHERE destination_id = ? AND local_id IN (\(placeholders))
                """, arguments: StatementArguments(arguments.map { $0 as! DatabaseValueConvertible })!)

                for row in rows {
                    if let syncedPhoto = try? parseSyncedPhoto(from: row) {
                        result[syncedPhoto.localID] = syncedPhoto
                    }
                }
            }

            return result
        }
    }

    /// Get synced photos with pagination for memory efficiency
    func getSyncedPhotosPaginated(destinationID: UUID, limit: Int, offset: Int) throws -> [SyncedPhoto] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM synced_photos
                WHERE destination_id = ?
                ORDER BY sync_date DESC
                LIMIT ? OFFSET ?
            """, arguments: [destinationID.uuidString, limit, offset])

            return try rows.map { try parseSyncedPhoto(from: $0) }
        }
    }

    /// Get count of synced photos for a destination
    func getSyncedPhotosCount(destinationID: UUID) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM synced_photos WHERE destination_id = ?
            """, arguments: [destinationID.uuidString]) ?? 0
        }
    }

    /// Batch update verification dates
    func updateVerificationDatesBatch(photoIDs: [UUID], date: Date) throws {
        guard !photoIDs.isEmpty else { return }

        try dbQueue.write { db in
            let chunkSize = 500
            for chunk in photoIDs.chunked(into: chunkSize) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                var arguments: [Any] = [date]
                arguments.append(contentsOf: chunk.map { $0.uuidString })

                try db.execute(sql: """
                    UPDATE synced_photos
                    SET last_verified_date = ?
                    WHERE id IN (\(placeholders))
                """, arguments: StatementArguments(arguments.map { $0 as! DatabaseValueConvertible })!)
            }
        }
        logger.info("Batch updated verification dates for \(photoIDs.count) photos")
    }

    // MARK: - Sync Jobs Operations

    func createSyncJob(_ job: SyncJob) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sync_jobs
                (id, destination_id, status, start_time, end_time, photos_scanned, photos_synced, photos_failed, bytes_transferred, average_speed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                job.id.uuidString,
                job.destinationID.uuidString,
                job.status.rawValue,
                job.startTime,
                job.endTime,
                job.photosScanned,
                job.photosSynced,
                job.photosFailed,
                job.bytesTransferred,
                job.averageSpeed
            ])
        }
    }

    func updateSyncJob(_ job: SyncJob) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE sync_jobs
                SET status = ?, end_time = ?, photos_scanned = ?, photos_synced = ?,
                    photos_failed = ?, bytes_transferred = ?, average_speed = ?
                WHERE id = ?
            """, arguments: [
                job.status.rawValue,
                job.endTime,
                job.photosScanned,
                job.photosSynced,
                job.photosFailed,
                job.bytesTransferred,
                job.averageSpeed,
                job.id.uuidString
            ])
        }
    }

    func getSyncJob(id: UUID) throws -> SyncJob? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM sync_jobs WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try parseSyncJob(from: row)
        }
    }

    func getRecentSyncJobs(limit: Int = 20) throws -> [SyncJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM sync_jobs
                ORDER BY start_time DESC
                LIMIT ?
            """, arguments: [limit])

            return try rows.map { try parseSyncJob(from: $0) }
        }
    }

    /// Clean up stale jobs that were left in "running" or "paused" state from a previous session
    /// This should be called on app startup to mark orphaned jobs as failed
    func cleanupStaleJobs() throws {
        try dbQueue.write { db in
            // Mark any "running" or "paused" jobs as "failed" since the app was restarted
            // These jobs were interrupted and never properly completed
            try db.execute(sql: """
                UPDATE sync_jobs
                SET status = 'failed', end_time = ?
                WHERE status IN ('running', 'paused')
            """, arguments: [Date()])
        }
        logger.info("Cleaned up stale sync jobs")
    }

    func deleteSyncJob(id: UUID) throws {
        try dbQueue.write { db in
            // Delete associated logs first
            try db.execute(sql: "DELETE FROM sync_logs WHERE job_id = ?", arguments: [id.uuidString])
            // Delete associated errors
            try db.execute(sql: "DELETE FROM sync_errors WHERE job_id = ?", arguments: [id.uuidString])
            // Delete the job
            try db.execute(sql: "DELETE FROM sync_jobs WHERE id = ?", arguments: [id.uuidString])
        }
        logger.info("Deleted sync job: \(id)")
    }

    func deleteAllSyncJobs() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM sync_logs")
            try db.execute(sql: "DELETE FROM sync_errors")
            try db.execute(sql: "DELETE FROM sync_jobs")
        }
        logger.info("Deleted all sync jobs")
    }

    // MARK: - Sync Logs Operations

    func saveSyncLog(_ log: SyncLogEntry) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sync_logs
                (id, job_id, timestamp, level, category, message, photo_id, details)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                log.id.uuidString,
                log.jobID.uuidString,
                log.timestamp,
                log.level.rawValue,
                log.category.rawValue,
                log.message,
                log.photoID,
                log.details
            ])
        }
    }

    func saveSyncLogs(_ logs: [SyncLogEntry]) throws {
        try dbQueue.write { db in
            for log in logs {
                try db.execute(sql: """
                    INSERT INTO sync_logs
                    (id, job_id, timestamp, level, category, message, photo_id, details)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    log.id.uuidString,
                    log.jobID.uuidString,
                    log.timestamp,
                    log.level.rawValue,
                    log.category.rawValue,
                    log.message,
                    log.photoID,
                    log.details
                ])
            }
        }
    }

    func getSyncLogs(jobID: UUID) throws -> [SyncLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM sync_logs
                WHERE job_id = ?
                ORDER BY timestamp ASC
            """, arguments: [jobID.uuidString])

            return rows.compactMap { try? parseSyncLog(from: $0) }
        }
    }

    func getSyncLogs(jobID: UUID, level: SyncLogEntry.LogLevel) throws -> [SyncLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM sync_logs
                WHERE job_id = ? AND level = ?
                ORDER BY timestamp ASC
            """, arguments: [jobID.uuidString, level.rawValue])

            return rows.compactMap { try? parseSyncLog(from: $0) }
        }
    }

    func getSyncLogCount(jobID: UUID) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sync_logs WHERE job_id = ?
            """, arguments: [jobID.uuidString]) ?? 0
        }
    }

    func getSyncLogSummary(jobID: UUID) throws -> [SyncLogEntry.LogLevel: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT level, COUNT(*) as count FROM sync_logs
                WHERE job_id = ?
                GROUP BY level
            """, arguments: [jobID.uuidString])

            var summary: [SyncLogEntry.LogLevel: Int] = [:]
            for row in rows {
                if let levelStr = row["level"] as? String,
                   let level = SyncLogEntry.LogLevel(rawValue: levelStr),
                   let count = row["count"] as? Int {
                    summary[level] = count
                }
            }
            return summary
        }
    }

    func deleteSyncLogs(jobID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM sync_logs WHERE job_id = ?", arguments: [jobID.uuidString])
        }
    }

    private func parseSyncLog(from row: Row) throws -> SyncLogEntry {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let jobIDString = row["job_id"] as? String,
              let jobID = UUID(uuidString: jobIDString),
              let levelString = row["level"] as? String,
              let level = SyncLogEntry.LogLevel(rawValue: levelString),
              let categoryString = row["category"] as? String,
              let category = SyncLogEntry.LogCategory(rawValue: categoryString) else {
            throw DatabaseError.queryFailed(query: "parse sync_log", underlying: NSError(domain: "Database", code: -1))
        }

        return SyncLogEntry(
            id: id,
            jobID: jobID,
            timestamp: row["timestamp"],
            level: level,
            category: category,
            message: row["message"],
            photoID: row["photo_id"],
            details: row["details"]
        )
    }

    // MARK: - Verification Logs Operations

    func saveVerificationLog(_ log: VerificationLogEntry) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO verification_logs
                (id, job_id, timestamp, level, category, message, photo_path, details)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                log.id.uuidString,
                log.jobID.uuidString,
                log.timestamp,
                log.level.rawValue,
                log.category.rawValue,
                log.message,
                log.photoPath,
                log.details
            ])
        }
    }

    func saveVerificationLogs(_ logs: [VerificationLogEntry]) throws {
        try dbQueue.write { db in
            for log in logs {
                try db.execute(sql: """
                    INSERT INTO verification_logs
                    (id, job_id, timestamp, level, category, message, photo_path, details)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    log.id.uuidString,
                    log.jobID.uuidString,
                    log.timestamp,
                    log.level.rawValue,
                    log.category.rawValue,
                    log.message,
                    log.photoPath,
                    log.details
                ])
            }
        }
    }

    func getVerificationLogs(jobID: UUID) throws -> [VerificationLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM verification_logs
                WHERE job_id = ?
                ORDER BY timestamp ASC
            """, arguments: [jobID.uuidString])

            return rows.compactMap { try? parseVerificationLog(from: $0) }
        }
    }

    func getVerificationLogs(jobID: UUID, level: VerificationLogEntry.LogLevel) throws -> [VerificationLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM verification_logs
                WHERE job_id = ? AND level = ?
                ORDER BY timestamp ASC
            """, arguments: [jobID.uuidString, level.rawValue])

            return rows.compactMap { try? parseVerificationLog(from: $0) }
        }
    }

    func getVerificationLogCount(jobID: UUID) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verification_logs WHERE job_id = ?
            """, arguments: [jobID.uuidString]) ?? 0
        }
    }

    func deleteVerificationLogs(jobID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM verification_logs WHERE job_id = ?", arguments: [jobID.uuidString])
        }
    }

    // MARK: - Log Cleanup

    /// Cleans up old logs and jobs older than the specified number of days
    /// - Parameter days: Number of days to retain logs (default 14)
    /// - Returns: Number of records deleted
    @discardableResult
    func cleanupOldLogs(olderThanDays days: Int = 14) throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var totalDeleted = 0

        try dbQueue.write { db in
            // Delete old sync logs
            try db.execute(sql: """
                DELETE FROM sync_logs WHERE timestamp < ?
            """, arguments: [cutoffDate])
            totalDeleted += db.changesCount

            // Delete old verification logs
            try db.execute(sql: """
                DELETE FROM verification_logs WHERE timestamp < ?
            """, arguments: [cutoffDate])
            totalDeleted += db.changesCount

            // Delete old sync jobs (and their orphaned logs will be cleaned by the above)
            try db.execute(sql: """
                DELETE FROM sync_jobs WHERE start_time < ?
            """, arguments: [cutoffDate])
            totalDeleted += db.changesCount

            // Delete old verification jobs
            try db.execute(sql: """
                DELETE FROM verification_jobs WHERE start_time < ?
            """, arguments: [cutoffDate])
            totalDeleted += db.changesCount
        }

        if totalDeleted > 0 {
            logger.info("Cleaned up \(totalDeleted) old log entries and jobs (older than \(days) days)")
        }

        return totalDeleted
    }

    private func parseVerificationLog(from row: Row) throws -> VerificationLogEntry {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let jobIDString = row["job_id"] as? String,
              let jobID = UUID(uuidString: jobIDString),
              let levelString = row["level"] as? String,
              let level = VerificationLogEntry.LogLevel(rawValue: levelString),
              let categoryString = row["category"] as? String,
              let category = VerificationLogEntry.VerificationLogCategory(rawValue: categoryString) else {
            throw DatabaseError.queryFailed(query: "parse verification_log", underlying: NSError(domain: "Database", code: -1))
        }

        return VerificationLogEntry(
            id: id,
            jobID: jobID,
            timestamp: row["timestamp"],
            level: level,
            category: category,
            message: row["message"],
            photoPath: row["photo_path"],
            details: row["details"]
        )
    }

    // MARK: - Sync Errors Operations

    func saveSyncError(_ error: SyncErrorEntry, jobID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sync_errors
                (id, job_id, photo_id, error_message, error_category, timestamp, retry_count)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                error.id.uuidString,
                jobID.uuidString,
                error.photoID,
                error.errorMessage,
                error.errorCategory,
                error.timestamp,
                error.retryCount
            ])
        }
    }

    func getSyncErrors(jobID: UUID) throws -> [SyncErrorEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM sync_errors
                WHERE job_id = ?
                ORDER BY timestamp DESC
            """, arguments: [jobID.uuidString])

            return rows.compactMap { parseSyncError(from: $0) }
        }
    }

    // MARK: - Destinations Operations

    func saveDestination(_ destination: DestinationRecord) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO destinations
                (id, name, type, config_json, created_at, last_health_check, health_status)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                destination.id.uuidString,
                destination.name,
                destination.type.rawValue,
                destination.configJSON,
                destination.createdAt,
                destination.lastHealthCheck,
                destination.healthStatus.rawValue
            ])
        }
    }

    func getDestination(id: UUID) throws -> DestinationRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM destinations WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try parseDestination(from: row)
        }
    }

    func getAllDestinations() throws -> [DestinationRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM destinations ORDER BY created_at DESC")
            return try rows.map { try parseDestination(from: $0) }
        }
    }

    func deleteDestination(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM destinations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func updateDestinationHealth(id: UUID, status: DestinationRecord.HealthStatus) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE destinations
                SET health_status = ?, last_health_check = ?
                WHERE id = ?
            """, arguments: [status.rawValue, Date(), id.uuidString])
        }
    }

    // MARK: - Statistics

    func getStats(destinationID: UUID) throws -> SyncStats {
        try dbQueue.read { db in
            let totalPhotos = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM synced_photos WHERE destination_id = ?
            """, arguments: [destinationID.uuidString]) ?? 0

            let totalBytes = try Int64.fetchOne(db, sql: """
                SELECT SUM(file_size) FROM synced_photos WHERE destination_id = ?
            """, arguments: [destinationID.uuidString]) ?? 0

            let lastSyncDate = try Date.fetchOne(db, sql: """
                SELECT MAX(sync_date) FROM synced_photos WHERE destination_id = ?
            """, arguments: [destinationID.uuidString])

            return SyncStats(
                totalPhotos: totalPhotos,
                totalBytes: totalBytes,
                lastSyncDate: lastSyncDate
            )
        }
    }

    // MARK: - Parsing Helpers

    private func parseSyncedPhoto(from row: Row) throws -> SyncedPhoto {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let destString = row["destination_id"] as? String,
              let destID = UUID(uuidString: destString) else {
            throw DatabaseError.queryFailed(query: "parse synced_photo", underlying: NSError(domain: "Database", code: -1))
        }

        return SyncedPhoto(
            id: id,
            localID: row["local_id"],
            remotePath: row["remote_path"],
            destinationID: destID,
            checksum: row["checksum"],
            syncDate: row["sync_date"],
            fileSize: row["file_size"],
            lastVerifiedDate: row["last_verified_date"],
            fileMetadata: row["file_metadata"]
        )
    }

    private func parseSyncJob(from row: Row) throws -> SyncJob {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let destString = row["destination_id"] as? String,
              let destID = UUID(uuidString: destString),
              let statusString = row["status"] as? String,
              let status = SyncJob.SyncJobStatus(rawValue: statusString) else {
            throw DatabaseError.queryFailed(query: "parse sync_job", underlying: NSError(domain: "Database", code: -1))
        }

        return SyncJob(
            id: id,
            destinationID: destID,
            status: status,
            startTime: row["start_time"],
            endTime: row["end_time"],
            photosScanned: row["photos_scanned"],
            photosSynced: row["photos_synced"],
            photosFailed: row["photos_failed"],
            bytesTransferred: row["bytes_transferred"],
            averageSpeed: row["average_speed"],
            errorLog: []
        )
    }

    private func parseSyncError(from row: Row) -> SyncErrorEntry? {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString) else {
            return nil
        }

        return SyncErrorEntry(
            id: id,
            photoID: row["photo_id"],
            errorMessage: row["error_message"],
            errorCategory: row["error_category"],
            timestamp: row["timestamp"],
            retryCount: row["retry_count"]
        )
    }

    private func parseDestination(from row: Row) throws -> DestinationRecord {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let typeString = row["type"] as? String,
              let type = DestinationType(rawValue: typeString),
              let healthString = row["health_status"] as? String,
              let health = DestinationRecord.HealthStatus(rawValue: healthString) else {
            throw DatabaseError.queryFailed(query: "parse destination", underlying: NSError(domain: "Database", code: -1))
        }

        return DestinationRecord(
            id: id,
            name: row["name"],
            type: type,
            configJSON: row["config_json"],
            createdAt: row["created_at"],
            lastHealthCheck: row["last_health_check"],
            healthStatus: health
        )
    }

    // MARK: - Verification Jobs Operations

    func saveVerificationJob(_ job: VerificationJob) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO verification_jobs
                (id, destination_id, type, start_time, end_time, total_photos, verified_count, mismatch_count, missing_count, error_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                job.id.uuidString,
                job.destinationID.uuidString,
                job.type.rawValue,
                job.startTime,
                job.endTime,
                job.totalPhotos,
                job.verifiedCount,
                job.mismatchCount,
                job.missingCount,
                job.errorCount
            ])
        }
        logger.info("Saved verification job: \(job.id)")
    }

    func getVerificationJob(id: UUID) throws -> VerificationJob? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM verification_jobs WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try parseVerificationJob(from: row)
        }
    }

    func getRecentVerificationJobs(limit: Int = 20) throws -> [VerificationJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM verification_jobs
                ORDER BY start_time DESC
                LIMIT ?
            """, arguments: [limit])

            return try rows.map { try parseVerificationJob(from: $0) }
        }
    }

    func getVerificationJobs(destinationID: UUID, limit: Int = 10) throws -> [VerificationJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM verification_jobs
                WHERE destination_id = ?
                ORDER BY start_time DESC
                LIMIT ?
            """, arguments: [destinationID.uuidString, limit])

            return try rows.map { try parseVerificationJob(from: $0) }
        }
    }

    func getLastVerificationJob(destinationID: UUID) throws -> VerificationJob? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM verification_jobs
                WHERE destination_id = ?
                ORDER BY start_time DESC
                LIMIT 1
            """, arguments: [destinationID.uuidString]) else {
                return nil
            }
            return try parseVerificationJob(from: row)
        }
    }

    func deleteVerificationJob(id: UUID) throws {
        try dbQueue.write { db in
            // Delete associated logs first
            try db.execute(sql: "DELETE FROM verification_logs WHERE job_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM verification_jobs WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func deleteVerificationJobs(destinationID: UUID) throws {
        try dbQueue.write { db in
            // Get all job IDs for this destination
            let jobIDs = try String.fetchAll(db, sql: """
                SELECT id FROM verification_jobs WHERE destination_id = ?
            """, arguments: [destinationID.uuidString])

            // Delete logs for all jobs
            for jobID in jobIDs {
                try db.execute(sql: "DELETE FROM verification_logs WHERE job_id = ?", arguments: [jobID])
            }

            try db.execute(sql: "DELETE FROM verification_jobs WHERE destination_id = ?", arguments: [destinationID.uuidString])
        }
    }

    private func parseVerificationJob(from row: Row) throws -> VerificationJob {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let destString = row["destination_id"] as? String,
              let destID = UUID(uuidString: destString),
              let typeString = row["type"] as? String,
              let jobType = VerificationJobType(rawValue: typeString) else {
            throw DatabaseError.queryFailed(query: "parse verification_job", underlying: NSError(domain: "Database", code: -1))
        }

        return VerificationJob(
            id: id,
            destinationID: destID,
            type: jobType,
            startTime: row["start_time"],
            endTime: row["end_time"],
            totalPhotos: row["total_photos"],
            verifiedCount: row["verified_count"],
            mismatchCount: row["mismatch_count"],
            missingCount: row["missing_count"],
            errorCount: row["error_count"]
        )
    }

    // MARK: - Scheduled Backup Jobs Operations

    func saveScheduledBackupJob(_ job: ScheduledBackupJob) throws {
        let encoder = JSONEncoder()
        let scheduleTypeData = try encoder.encode(job.scheduleType)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO scheduled_backup_jobs
                (id, destination_id, name, is_enabled, schedule_type_json, filter, created_at, last_run_time, next_run_time, last_run_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                job.id.uuidString,
                job.destinationID.uuidString,
                job.name,
                job.isEnabled,
                scheduleTypeData,
                job.filter.rawValue,
                job.createdAt,
                job.lastRunTime,
                job.nextRunTime,
                job.lastRunStatus?.rawValue
            ])
        }
        logger.info("Saved scheduled backup job: \(job.name)")
    }

    func getScheduledBackupJob(id: UUID) throws -> ScheduledBackupJob? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_backup_jobs WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try parseScheduledBackupJob(from: row)
        }
    }

    func getAllScheduledBackupJobs() throws -> [ScheduledBackupJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM scheduled_backup_jobs ORDER BY created_at DESC")
            return rows.compactMap { try? parseScheduledBackupJob(from: $0) }
        }
    }

    func getEnabledScheduledBackupJobs() throws -> [ScheduledBackupJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM scheduled_backup_jobs
                WHERE is_enabled = 1
                ORDER BY next_run_time ASC
            """)
            return rows.compactMap { try? parseScheduledBackupJob(from: $0) }
        }
    }

    func getScheduledBackupJobs(destinationID: UUID) throws -> [ScheduledBackupJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM scheduled_backup_jobs
                WHERE destination_id = ?
                ORDER BY created_at DESC
            """, arguments: [destinationID.uuidString])
            return rows.compactMap { try? parseScheduledBackupJob(from: $0) }
        }
    }

    func getJobsDueForExecution(before date: Date = Date()) throws -> [ScheduledBackupJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM scheduled_backup_jobs
                WHERE is_enabled = 1 AND next_run_time IS NOT NULL AND next_run_time <= ?
                ORDER BY next_run_time ASC
            """, arguments: [date])
            return rows.compactMap { try? parseScheduledBackupJob(from: $0) }
        }
    }

    func updateScheduledJobAfterRun(id: UUID, lastRunTime: Date, nextRunTime: Date?, status: SyncJob.SyncJobStatus) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE scheduled_backup_jobs
                SET last_run_time = ?, next_run_time = ?, last_run_status = ?
                WHERE id = ?
            """, arguments: [lastRunTime, nextRunTime, status.rawValue, id.uuidString])
        }
    }

    func toggleScheduledBackupJob(id: UUID, isEnabled: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE scheduled_backup_jobs
                SET is_enabled = ?
                WHERE id = ?
            """, arguments: [isEnabled, id.uuidString])
        }
    }

    func deleteScheduledBackupJob(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM scheduled_backup_jobs WHERE id = ?", arguments: [id.uuidString])
        }
        logger.info("Deleted scheduled backup job: \(id)")
    }

    func deleteScheduledBackupJobs(destinationID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM scheduled_backup_jobs WHERE destination_id = ?", arguments: [destinationID.uuidString])
        }
    }

    private func parseScheduledBackupJob(from row: Row) throws -> ScheduledBackupJob {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let destString = row["destination_id"] as? String,
              let destID = UUID(uuidString: destString),
              let scheduleTypeData = row["schedule_type_json"] as? Data,
              let filterString = row["filter"] as? String,
              let filter = ScheduledBackupJob.DateRangeFilterType(rawValue: filterString) else {
            throw DatabaseError.queryFailed(query: "parse scheduled_backup_job", underlying: NSError(domain: "Database", code: -1))
        }

        let decoder = JSONDecoder()
        let scheduleType = try decoder.decode(ScheduledBackupJob.ScheduleType.self, from: scheduleTypeData)

        var lastRunStatus: SyncJob.SyncJobStatus? = nil
        if let statusString = row["last_run_status"] as? String {
            lastRunStatus = SyncJob.SyncJobStatus(rawValue: statusString)
        }

        return ScheduledBackupJob(
            id: id,
            destinationID: destID,
            name: row["name"],
            isEnabled: row["is_enabled"],
            scheduleType: scheduleType,
            filter: filter,
            createdAt: row["created_at"],
            lastRunTime: row["last_run_time"],
            nextRunTime: row["next_run_time"],
            lastRunStatus: lastRunStatus
        )
    }
}

// MARK: - Sync Statistics

struct SyncStats {
    let totalPhotos: Int
    let totalBytes: Int64
    let lastSyncDate: Date?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
