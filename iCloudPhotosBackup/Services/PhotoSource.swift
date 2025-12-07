import Foundation
import Photos

// MARK: - Photo Metadata

struct PhotoMetadata {
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let assetType: PHAssetMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64?
    let originalFilename: String?

    // Extended metadata
    let cameraModel: String?
    let location: CLLocation?

    /// Unique identifier for deduplication
    var uniqueID: String {
        return localIdentifier
    }
}

// MARK: - Photo Export Result

struct PhotoExportResult {
    let photoMetadata: PhotoMetadata
    let exportedFileURL: URL
    let fileSize: Int64
    let checksum: String
}

// MARK: - Date Range Filter

enum DateRangeFilter: Hashable {
    case last24Hours
    case last7Days
    case last30Days
    case last90Days
    case customRange(start: Date, end: Date)
    case fullLibrary

    var dateRange: (start: Date?, end: Date?) {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .last24Hours:
            let start = calendar.date(byAdding: .hour, value: -24, to: now)
            return (start, now)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)
            return (start, now)
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -90, to: now)
            return (start, now)
        case .customRange(let start, let end):
            return (start, end)
        case .fullLibrary:
            return (nil, nil)
        }
    }
}

// MARK: - Photo Source Protocol

/// Protocol defining the interface for photo sources (PhotoKit)
/// ⚠️ CRITICAL: All implementations MUST be read-only
/// We request .readWrite permission (required by Apple) but NEVER use write/mutation APIs
///
/// PROHIBITED APIs (never use):
/// - PHAssetChangeRequest
/// - PHAssetCollectionChangeRequest
/// - PHAssetCreationRequest
/// - PHPhotoLibrary.shared().performChanges()
/// - Any method that modifies, deletes, or adds photos
protocol PhotoSource: AnyObject {
    /// Request authorization to access the photo library
    /// Note: Requires .readWrite but we only use read APIs
    func requestAuthorization() async throws -> Bool

    /// Fetch photos matching the given filter
    /// - Parameter filter: Date range filter
    /// - Returns: Array of photo metadata
    func fetchPhotos(filter: DateRangeFilter) async throws -> [PhotoMetadata]

    /// Export a photo to a temporary location
    /// - Parameters:
    ///   - photo: Photo metadata to export
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Export result with file URL and checksum
    func exportPhoto(_ photo: PhotoMetadata, progress: @escaping (Double) -> Void) async throws -> PhotoExportResult

    /// Cancel ongoing export operations
    func cancelExport()
}
