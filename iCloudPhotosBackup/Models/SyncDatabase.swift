import Foundation

/// Database models for sync state tracking
/// Using simple struct models that can be mapped to GRDB or SwiftData

// MARK: - Synced Photo Record

struct SyncedPhoto: Codable, Identifiable {
    let id: UUID
    let localID: String  // PHAsset.localIdentifier
    let remotePath: String
    let destinationID: UUID
    let checksum: String
    let syncDate: Date
    let fileSize: Int64
    let lastVerifiedDate: Date?
    let fileMetadata: Data?  // JSON blob for extended metadata

    init(
        id: UUID = UUID(),
        localID: String,
        remotePath: String,
        destinationID: UUID,
        checksum: String,
        syncDate: Date = Date(),
        fileSize: Int64,
        lastVerifiedDate: Date? = nil,
        fileMetadata: Data? = nil
    ) {
        self.id = id
        self.localID = localID
        self.remotePath = remotePath
        self.destinationID = destinationID
        self.checksum = checksum
        self.syncDate = syncDate
        self.fileSize = fileSize
        self.lastVerifiedDate = lastVerifiedDate
        self.fileMetadata = fileMetadata
    }
}

// MARK: - Sync Job Record

struct SyncJob: Codable, Identifiable {
    let id: UUID
    let destinationID: UUID
    var status: SyncJobStatus
    let startTime: Date
    var endTime: Date?
    var photosScanned: Int
    var photosSynced: Int
    var photosFailed: Int
    var bytesTransferred: Int64
    var averageSpeed: Double?  // MB/s
    var errorLog: [SyncErrorEntry]

    enum SyncJobStatus: String, Codable {
        case running
        case paused
        case completed
        case failed
        case cancelled
    }

    init(
        id: UUID = UUID(),
        destinationID: UUID,
        status: SyncJobStatus = .running,
        startTime: Date = Date(),
        endTime: Date? = nil,
        photosScanned: Int = 0,
        photosSynced: Int = 0,
        photosFailed: Int = 0,
        bytesTransferred: Int64 = 0,
        averageSpeed: Double? = nil,
        errorLog: [SyncErrorEntry] = []
    ) {
        self.id = id
        self.destinationID = destinationID
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.photosScanned = photosScanned
        self.photosSynced = photosSynced
        self.photosFailed = photosFailed
        self.bytesTransferred = bytesTransferred
        self.averageSpeed = averageSpeed
        self.errorLog = errorLog
    }
}

// MARK: - Sync Error Entry

struct SyncErrorEntry: Codable, Identifiable {
    let id: UUID
    let photoID: String
    let errorMessage: String
    let errorCategory: String
    let timestamp: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        photoID: String,
        errorMessage: String,
        errorCategory: String,
        timestamp: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.photoID = photoID
        self.errorMessage = errorMessage
        self.errorCategory = errorCategory
        self.timestamp = timestamp
        self.retryCount = retryCount
    }
}

// MARK: - Sync Log Entry

struct SyncLogEntry: Codable, Identifiable {
    let id: UUID
    let jobID: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let photoID: String?
    let details: String?

    enum LogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case success = "SUCCESS"

        var icon: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .success: return "checkmark.circle"
            }
        }
    }

    enum LogCategory: String, Codable, CaseIterable {
        case general = "General"
        case connection = "Connection"
        case export = "Export"
        case upload = "Upload"
        case encryption = "Encryption"
        case deduplication = "Deduplication"
        case database = "Database"
        case cleanup = "Cleanup"

        var icon: String {
            switch self {
            case .general: return "doc.text"
            case .connection: return "network"
            case .export: return "square.and.arrow.up"
            case .upload: return "icloud.and.arrow.up"
            case .encryption: return "lock.shield"
            case .deduplication: return "doc.on.doc"
            case .database: return "externaldrive"
            case .cleanup: return "trash"
            }
        }
    }

    init(
        id: UUID = UUID(),
        jobID: UUID,
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        photoID: String? = nil,
        details: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.photoID = photoID
        self.details = details
    }
}

// MARK: - Destination Record

struct DestinationRecord: Codable, Identifiable {
    let id: UUID
    var name: String
    let type: DestinationType
    var configJSON: Data  // Serialized configuration
    let createdAt: Date
    var lastHealthCheck: Date?
    var healthStatus: HealthStatus

    enum HealthStatus: String, Codable {
        case unknown
        case healthy
        case degraded
        case unhealthy
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: DestinationType,
        configJSON: Data,
        createdAt: Date = Date(),
        lastHealthCheck: Date? = nil,
        healthStatus: HealthStatus = .unknown
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.configJSON = configJSON
        self.createdAt = createdAt
        self.lastHealthCheck = lastHealthCheck
        self.healthStatus = healthStatus
    }
}

// MARK: - Deleted Photo Record

struct DeletedPhoto: Codable, Identifiable {
    let id: UUID
    let localID: String
    let deletionDate: Date
    let destinationID: UUID
    let remotePath: String

    init(
        id: UUID = UUID(),
        localID: String,
        deletionDate: Date = Date(),
        destinationID: UUID,
        remotePath: String
    ) {
        self.id = id
        self.localID = localID
        self.deletionDate = deletionDate
        self.destinationID = destinationID
        self.remotePath = remotePath
    }
}

// MARK: - Verification Job Record

struct VerificationJob: Codable, Identifiable {
    let id: UUID
    let destinationID: UUID
    let type: VerificationJobType
    let startTime: Date
    var endTime: Date?
    var totalPhotos: Int
    var verifiedCount: Int
    var mismatchCount: Int
    var missingCount: Int
    var errorCount: Int

    var isFullyVerified: Bool {
        mismatchCount == 0 && missingCount == 0 && errorCount == 0
    }

    var successRate: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(verifiedCount) / Double(totalPhotos)
    }

    init(
        id: UUID = UUID(),
        destinationID: UUID,
        type: VerificationJobType,
        startTime: Date = Date(),
        endTime: Date? = nil,
        totalPhotos: Int = 0,
        verifiedCount: Int = 0,
        mismatchCount: Int = 0,
        missingCount: Int = 0,
        errorCount: Int = 0
    ) {
        self.id = id
        self.destinationID = destinationID
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.totalPhotos = totalPhotos
        self.verifiedCount = verifiedCount
        self.mismatchCount = mismatchCount
        self.missingCount = missingCount
        self.errorCount = errorCount
    }
}

// MARK: - Verification Log Entry

struct VerificationLogEntry: Codable, Identifiable {
    let id: UUID
    let jobID: UUID
    let timestamp: Date
    let level: LogLevel
    let category: VerificationLogCategory
    let message: String
    let photoPath: String?
    let details: String?

    enum LogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case success = "SUCCESS"

        var icon: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .success: return "checkmark.circle"
            }
        }

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            case .success: return "green"
            }
        }
    }

    enum VerificationLogCategory: String, Codable, CaseIterable {
        case general = "General"
        case connection = "Connection"
        case verification = "Verification"
        case checksum = "Checksum"
        case missing = "Missing"
        case mismatch = "Mismatch"

        var icon: String {
            switch self {
            case .general: return "doc.text"
            case .connection: return "network"
            case .verification: return "checkmark.shield"
            case .checksum: return "number.circle"
            case .missing: return "questionmark.folder"
            case .mismatch: return "exclamationmark.triangle"
            }
        }
    }

    init(
        id: UUID = UUID(),
        jobID: UUID,
        timestamp: Date = Date(),
        level: LogLevel,
        category: VerificationLogCategory,
        message: String,
        photoPath: String? = nil,
        details: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.photoPath = photoPath
        self.details = details
    }
}

// MARK: - Scheduled Backup Job Record

struct ScheduledBackupJob: Codable, Identifiable {
    let id: UUID
    let destinationID: UUID
    var name: String
    var isEnabled: Bool
    var scheduleType: ScheduleType
    var filter: DateRangeFilterType
    let createdAt: Date
    var lastRunTime: Date?
    var nextRunTime: Date?
    var lastRunStatus: SyncJob.SyncJobStatus?

    enum ScheduleType: Codable, Equatable {
        case oneTime(scheduledDate: Date)
        case daily(hour: Int, minute: Int)
        case weekly(dayOfWeek: Int, hour: Int, minute: Int)  // 1 = Sunday, 7 = Saturday
        case custom(intervalSeconds: TimeInterval)

        var displayName: String {
            switch self {
            case .oneTime:
                return "One Time"
            case .daily:
                return "Daily"
            case .weekly:
                return "Weekly"
            case .custom:
                return "Custom"
            }
        }

        var description: String {
            switch self {
            case .oneTime(let date):
                return "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))"
            case .daily(let hour, let minute):
                return "Daily at \(String(format: "%02d:%02d", hour, minute))"
            case .weekly(let day, let hour, let minute):
                let dayName = Calendar.current.weekdaySymbols[day - 1]
                return "Every \(dayName) at \(String(format: "%02d:%02d", hour, minute))"
            case .custom(let interval):
                let hours = Int(interval) / 3600
                if hours >= 24 {
                    return "Every \(hours / 24) day(s)"
                } else {
                    return "Every \(hours) hour(s)"
                }
            }
        }
    }

    enum DateRangeFilterType: String, Codable, CaseIterable {
        case last24Hours = "Last 24 Hours"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        case last90Days = "Last 90 Days"
        case fullLibrary = "Full Library"

        var toDateRangeFilter: DateRangeFilter {
            switch self {
            case .last24Hours: return .last24Hours
            case .last7Days: return .last7Days
            case .last30Days: return .last30Days
            case .last90Days: return .last90Days
            case .fullLibrary: return .fullLibrary
            }
        }
    }

    init(
        id: UUID = UUID(),
        destinationID: UUID,
        name: String,
        isEnabled: Bool = true,
        scheduleType: ScheduleType,
        filter: DateRangeFilterType = .fullLibrary,
        createdAt: Date = Date(),
        lastRunTime: Date? = nil,
        nextRunTime: Date? = nil,
        lastRunStatus: SyncJob.SyncJobStatus? = nil
    ) {
        self.id = id
        self.destinationID = destinationID
        self.name = name
        self.isEnabled = isEnabled
        self.scheduleType = scheduleType
        self.filter = filter
        self.createdAt = createdAt
        self.lastRunTime = lastRunTime
        self.nextRunTime = nextRunTime
        self.lastRunStatus = lastRunStatus
    }

    /// Calculate the next run time based on schedule type
    func calculateNextRunTime(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch scheduleType {
        case .oneTime(let scheduledDate):
            return scheduledDate > date ? scheduledDate : nil

        case .daily(let hour, let minute):
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let nextRun = calendar.date(from: components) else { return nil }

            // If the time has passed today, schedule for tomorrow
            if nextRun <= date {
                return calendar.date(byAdding: .day, value: 1, to: nextRun)
            }
            return nextRun

        case .weekly(let dayOfWeek, let hour, let minute):
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let currentWeekday = components.weekday ?? 1

            // Calculate days until target weekday
            var daysUntil = dayOfWeek - currentWeekday
            if daysUntil < 0 {
                daysUntil += 7
            }

            guard let targetDate = calendar.date(byAdding: .day, value: daysUntil, to: date) else { return nil }

            var targetComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            targetComponents.hour = hour
            targetComponents.minute = minute
            targetComponents.second = 0

            guard let nextRun = calendar.date(from: targetComponents) else { return nil }

            // If it's today but the time has passed, schedule for next week
            if daysUntil == 0 && nextRun <= date {
                return calendar.date(byAdding: .day, value: 7, to: nextRun)
            }
            return nextRun

        case .custom(let intervalSeconds):
            if let lastRun = lastRunTime {
                return lastRun.addingTimeInterval(intervalSeconds)
            }
            return date.addingTimeInterval(intervalSeconds)
        }
    }
}

// MARK: - Database Schema Version

struct DatabaseSchemaVersion: Codable {
    let version: Int
    let appliedAt: Date

    static let current = DatabaseSchemaVersion(version: 1, appliedAt: Date())
}
