import Foundation
import Photos
import CryptoKit
import OSLog

/// Service for accessing iCloud Photos via PhotoKit
/// ⚠️ CRITICAL: This class is READ-ONLY. We request .readWrite permission (required by Apple)
/// but NEVER use any write/mutation APIs.
///
/// PROHIBITED APIs (never call these):
/// - PHAssetChangeRequest
/// - PHAssetCollectionChangeRequest
/// - PHAssetCreationRequest
/// - PHPhotoLibrary.shared().performChanges()
final class PhotoLibraryService: PhotoSource, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "PhotoLibrary")
    private var imageManager: PHImageManager
    private var exportRequestIDs: [PHImageRequestID] = []
    private let exportQueue = DispatchQueue(label: "com.icloudphotosbackup.export", qos: .userInitiated)

    init() {
        self.imageManager = PHImageManager.default()
        logger.info("PhotoLibraryService initialized (READ-ONLY mode)")
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        logger.info("Requesting photo library authorization")

        // Note: We request .readWrite because Apple doesn't provide .readOnly option
        // However, we NEVER use any write operations
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        switch status {
        case .authorized:
            logger.info("Photo library authorization granted")
            return true

        case .denied:
            logger.error("Photo library authorization denied")
            throw PhotoLibraryError.authorizationDenied

        case .restricted:
            logger.error("Photo library authorization restricted")
            throw PhotoLibraryError.authorizationRestricted

        case .limited:
            logger.warning("Photo library authorization limited - only selected photos available")
            return true

        case .notDetermined:
            logger.error("Photo library authorization not determined")
            return false

        @unknown default:
            logger.error("Unknown photo library authorization status")
            return false
        }
    }

    // MARK: - Fetch Photos

    func fetchPhotos(filter: DateRangeFilter) async throws -> [PhotoMetadata] {
        logger.info("Fetching photos with filter: \(String(describing: filter))")

        // First check current authorization status
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        logger.info("Current photo library authorization status: \(String(describing: currentStatus.rawValue))")

        if currentStatus != .authorized && currentStatus != .limited {
            logger.error("Photo library not authorized. Status: \(currentStatus.rawValue)")
            throw PhotoLibraryError.authorizationDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            exportQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PhotoLibraryError.fetchFailed(underlying: NSError(domain: "PhotoLibrary", code: -1)))
                    return
                }

                let fetchOptions = PHFetchOptions()
                fetchOptions.includeHiddenAssets = false
                fetchOptions.includeAllBurstAssets = false

                // Apply date range filter
                let (startDate, endDate) = filter.dateRange
                if let start = startDate, let end = endDate {
                    self.logger.info("Filtering photos from \(start) to \(end)")
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate >= %@ AND creationDate <= %@",
                        start as NSDate,
                        end as NSDate
                    )
                } else if let start = startDate {
                    self.logger.info("Filtering photos from \(start)")
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate >= %@",
                        start as NSDate
                    )
                } else if let end = endDate {
                    self.logger.info("Filtering photos until \(end)")
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate <= %@",
                        end as NSDate
                    )
                } else {
                    self.logger.info("Fetching all photos (no date filter)")
                }

                // Sort by creation date (oldest first for consistent processing)
                fetchOptions.sortDescriptors = [
                    NSSortDescriptor(key: "creationDate", ascending: true)
                ]

                // First, try to get a count of ALL photos without filter to verify access
                let allPhotosResult = PHAsset.fetchAssets(with: .image, options: nil)
                self.logger.info("Total photos in library (images only): \(allPhotosResult.count)")

                let allVideosResult = PHAsset.fetchAssets(with: .video, options: nil)
                self.logger.info("Total videos in library: \(allVideosResult.count)")

                // Now fetch with our filter
                let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
                var metadata: [PhotoMetadata] = []

                fetchResult.enumerateObjects { asset, _, _ in
                    let photoMeta = self.extractMetadata(from: asset)
                    metadata.append(photoMeta)
                }

                self.logger.info("Fetched \(metadata.count) photos matching filter")
                continuation.resume(returning: metadata)
            }
        }
    }

    // MARK: - Extract Metadata

    private func extractMetadata(from asset: PHAsset) -> PhotoMetadata {
        // Extract location with proper timezone handling
        let location = asset.location

        // Get original filename from resources
        var originalFilename: String?
        var fileSize: Int64?

        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            originalFilename = resource.originalFilename

            // Try to get file size (this is a private API but commonly used)
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                fileSize = size
            }
        }

        return PhotoMetadata(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            assetType: asset.mediaType,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: fileSize,
            originalFilename: originalFilename,
            cameraModel: nil,  // Camera model not directly accessible from PHAsset
            location: location
        )
    }

    // MARK: - Export Photo

    func exportPhoto(_ photo: PhotoMetadata, progress: @escaping (Double) -> Void) async throws -> PhotoExportResult {
        logger.info("Exporting photo: \(photo.localIdentifier)")

        return try await withCheckedThrowingContinuation { continuation in
            exportQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: photo.localIdentifier, underlying: nil))
                    return
                }

                // Fetch the asset
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
                guard let asset = fetchResult.firstObject else {
                    self.logger.error("Asset not found: \(photo.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: photo.localIdentifier, underlying: nil))
                    return
                }

                // Determine export strategy based on asset type
                switch asset.mediaType {
                case .image:
                    self.exportImage(asset: asset, metadata: photo, progress: progress, continuation: continuation)

                case .video:
                    self.exportVideo(asset: asset, metadata: photo, progress: progress, continuation: continuation)

                case .audio:
                    self.logger.warning("Audio assets not supported: \(photo.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.unsupportedAssetType(type: "audio"))

                case .unknown:
                    self.logger.warning("Unknown asset type: \(photo.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.unsupportedAssetType(type: "unknown"))

                @unknown default:
                    self.logger.warning("Unsupported asset type: \(photo.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.unsupportedAssetType(type: "unknown"))
                }
            }
        }
    }

    // MARK: - Export Image

    private func exportImage(
        asset: PHAsset,
        metadata: PhotoMetadata,
        progress: @escaping (Double) -> Void,
        continuation: CheckedContinuation<PhotoExportResult, Error>
    ) {
        let options = PHImageRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // Progress handler for iCloud downloads
        options.progressHandler = { downloadProgress, error, _, _ in
            if let error = error {
                self.logger.error("iCloud download error: \(error.localizedDescription)")
            }
            progress(downloadProgress)
        }

        let requestID = imageManager.requestImageDataAndOrientation(for: asset, options: options) { imageData, dataUTI, _, info in
            guard let imageData = imageData else {
                if let error = info?[PHImageErrorKey] as? Error {
                    self.logger.error("Failed to export image: \(error.localizedDescription)")
                    continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: error))
                } else if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    self.logger.info("Image export cancelled: \(metadata.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: nil))
                } else if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                    self.logger.error("Photo is in iCloud but download failed: \(metadata.localIdentifier)")
                    continuation.resume(throwing: PhotoLibraryError.iCloudDownloadFailed(photoID: metadata.localIdentifier))
                } else {
                    continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: nil))
                }
                return
            }

            do {
                // Create temporary file
                let tempURL = try self.createTempFile(for: metadata, dataUTI: dataUTI)

                // Write image data
                try imageData.write(to: tempURL)

                // Calculate checksum
                let checksum = SHA256.hash(data: imageData)
                let checksumString = checksum.compactMap { String(format: "%02x", $0) }.joined()

                let result = PhotoExportResult(
                    photoMetadata: metadata,
                    exportedFileURL: tempURL,
                    fileSize: Int64(imageData.count),
                    checksum: checksumString
                )

                self.logger.info("Successfully exported image: \(metadata.localIdentifier), size: \(imageData.count) bytes")
                continuation.resume(returning: result)

            } catch {
                self.logger.error("Failed to write exported image: \(error.localizedDescription)")
                continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: error))
            }
        }

        exportRequestIDs.append(requestID)
    }

    // MARK: - Export Video

    private func exportVideo(
        asset: PHAsset,
        metadata: PhotoMetadata,
        progress: @escaping (Double) -> Void,
        continuation: CheckedContinuation<PhotoExportResult, Error>
    ) {
        let options = PHVideoRequestOptions()
        options.version = .original
        // Note: deliveryMode is only applicable for .current version requests, not .original
        options.isNetworkAccessAllowed = true

        options.progressHandler = { downloadProgress, error, _, _ in
            if let error = error {
                self.logger.error("iCloud video download error: \(error.localizedDescription)")
            }
            progress(downloadProgress)
        }

        let requestID = imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            guard let urlAsset = avAsset as? AVURLAsset else {
                self.logger.error("Failed to get video URL asset")
                continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: nil))
                return
            }

            do {
                let sourceURL = urlAsset.url

                // Read video data
                let videoData = try Data(contentsOf: sourceURL)

                // Create temporary file
                let tempURL = try self.createTempFile(for: metadata, dataUTI: "public.movie")

                // Copy video file
                try videoData.write(to: tempURL)

                // Calculate checksum
                let checksum = SHA256.hash(data: videoData)
                let checksumString = checksum.compactMap { String(format: "%02x", $0) }.joined()

                let result = PhotoExportResult(
                    photoMetadata: metadata,
                    exportedFileURL: tempURL,
                    fileSize: Int64(videoData.count),
                    checksum: checksumString
                )

                self.logger.info("Successfully exported video: \(metadata.localIdentifier), size: \(videoData.count) bytes")
                continuation.resume(returning: result)

            } catch {
                self.logger.error("Failed to export video: \(error.localizedDescription)")
                continuation.resume(throwing: PhotoLibraryError.exportFailed(photoID: metadata.localIdentifier, underlying: error))
            }
        }

        exportRequestIDs.append(requestID)
    }

    // MARK: - Helper Methods

    private func createTempFile(for metadata: PhotoMetadata, dataUTI: String?) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let appTempDir = tempDir.appendingPathComponent("iCloudPhotosBackup", isDirectory: true)

        // Create temp directory if needed
        if !FileManager.default.fileExists(atPath: appTempDir.path) {
            try FileManager.default.createDirectory(at: appTempDir, withIntermediateDirectories: true)
        }

        // Determine file extension
        var fileExtension = "jpg"
        if let uti = dataUTI {
            if uti.contains("heic") || uti.contains("heif") {
                fileExtension = "heic"
            } else if uti.contains("png") {
                fileExtension = "png"
            } else if uti.contains("raw") {
                fileExtension = "raw"
            } else if uti.contains("movie") || uti.contains("video") {
                fileExtension = "mov"
            }
        }

        // Use original filename or generate one
        let filename: String
        if let originalName = metadata.originalFilename {
            filename = originalName
        } else {
            // Generate filename from creation date and asset ID
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateString = metadata.creationDate.map { dateFormatter.string(from: $0) } ?? "unknown"
            let assetID = metadata.localIdentifier.replacingOccurrences(of: "/", with: "_")
            filename = "\(dateString)_\(assetID).\(fileExtension)"
        }

        return appTempDir.appendingPathComponent(filename)
    }

    // MARK: - Cancel Export

    func cancelExport() {
        logger.info("Cancelling all export operations")

        exportQueue.async { [weak self] in
            guard let self = self else { return }

            for requestID in self.exportRequestIDs {
                self.imageManager.cancelImageRequest(requestID)
            }

            self.exportRequestIDs.removeAll()
            self.logger.info("All export operations cancelled")
        }
    }
}
