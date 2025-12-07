import Foundation
import Observation

// MARK: - Sync Job State

enum SyncJobState: String, Codable {
    case idle
    case preparing
    case syncing
    case paused
    case completed
    case failed
}

// MARK: - Sync Progress

@Observable
class SyncProgress {
    var totalPhotos: Int = 0
    var photosCompleted: Int = 0
    var photosFailed: Int = 0
    var currentPhotoName: String?
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64 = 0
    var currentSpeed: Double = 0  // MB/s
    var averageSpeed: Double = 0  // MB/s
    var estimatedTimeRemaining: TimeInterval?

    var progress: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(photosCompleted) / Double(totalPhotos)
    }
}

// MARK: - Sync Engine Protocol

/// Protocol defining the interface for the sync engine
/// Orchestrates backup operations between photo source and destinations
protocol SyncEngine: AnyObject {
    /// Current sync state
    var state: SyncJobState { get }

    /// Current progress
    var progress: SyncProgress { get }

    /// Current job ID (nil when not syncing)
    var currentJobID: UUID? { get }

    /// Start a sync job
    /// - Parameters:
    ///   - source: Photo source to read from
    ///   - destination: Backup destination to write to
    ///   - filter: Date range filter for photos
    func startSync(source: PhotoSource, destination: BackupDestination, filter: DateRangeFilter) async throws

    /// Pause the current sync job
    func pause() async throws

    /// Resume a paused sync job
    func resume() async throws

    /// Cancel the current sync job
    func cancel() async throws

    /// Flush any pending logs to database
    func flushLogs()
}

// MARK: - Verification Job Type

enum VerificationJobType: String, Codable, CaseIterable {
    case full           // Verify all synced photos
    case quick          // Random sample verification
    case incremental    // Only verify recently synced or never-verified photos
}
