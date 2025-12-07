import Foundation

// MARK: - Destination Types

enum DestinationType: String, Codable, CaseIterable {
    case s3
    case smb
    case sftp
    case ftp
}

// MARK: - Remote File Metadata

struct RemoteFileMetadata: Identifiable {
    let path: String
    let size: Int64
    let modifiedDate: Date
    let checksum: String?

    var id: String { path }

    /// Extract filename from path
    var filename: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Check if this is an image file
    var isImage: Bool {
        let ext = filename.lowercased().split(separator: ".").last ?? ""
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "bmp", "webp"].contains(String(ext))
    }

    /// Check if this is a video file
    var isVideo: Bool {
        let ext = filename.lowercased().split(separator: ".").last ?? ""
        return ["mov", "mp4", "m4v", "avi", "mkv", "webm"].contains(String(ext))
    }

    /// Formatted file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Upload Result

struct UploadResult {
    let remotePath: String
    let checksum: String
    let size: Int64
    let uploadDuration: TimeInterval
}

// MARK: - Backup Destination Protocol

/// Protocol defining the interface for backup destinations (S3, SMB, SFTP, etc.)
/// All implementations must be read-only for the photo source
protocol BackupDestination: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var type: DestinationType { get }

    /// Connect to the destination and verify credentials
    func connect() async throws

    /// Disconnect from the destination
    func disconnect() async throws

    /// Upload a file to the destination with progress tracking
    /// - Parameters:
    ///   - file: Local file URL to upload
    ///   - remotePath: Remote path where file should be stored
    ///   - progress: Callback for upload progress (0.0 to 1.0)
    /// - Returns: Upload result with metadata
    func upload(file: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws -> UploadResult

    /// Check if a file exists at the remote path
    /// - Parameter remotePath: Remote path to check
    /// - Returns: True if file exists
    func fileExists(at remotePath: String) async throws -> Bool

    /// Get metadata for a file at the remote path
    /// - Parameter remotePath: Remote path
    /// - Returns: File metadata or nil if not found
    func getFileMetadata(at remotePath: String) async throws -> RemoteFileMetadata?

    /// List files in a remote directory
    /// - Parameter directory: Remote directory path
    /// - Returns: Array of file metadata
    func listFiles(in directory: String) async throws -> [RemoteFileMetadata]

    /// Delete a file at the remote path
    /// - Parameter remotePath: Remote path to delete
    func delete(at remotePath: String) async throws

    /// Test connection to the destination
    /// - Returns: True if connection successful
    func testConnection() async throws -> Bool

    /// Verify checksum of remote file
    /// - Parameters:
    ///   - remotePath: Remote path to verify
    ///   - expectedChecksum: Expected checksum value
    /// - Returns: True if checksums match
    func verifyChecksum(remotePath: String, expectedChecksum: String) async throws -> Bool

    /// Download a file from the remote destination
    /// - Parameters:
    ///   - remotePath: Remote path to download
    ///   - progress: Callback for download progress (0.0 to 1.0)
    /// - Returns: File data
    func downloadFile(at remotePath: String, progress: @escaping (Double) -> Void) async throws -> Data
}

// MARK: - Destination Configuration Protocol

/// Protocol for destination-specific configuration
protocol DestinationConfiguration: Codable {
    var id: UUID { get }
    var name: String { get }
    var type: DestinationType { get }
    var createdAt: Date { get }

    /// Validate the configuration
    /// - Throws: ValidationError if configuration is invalid
    func validate() throws
}
