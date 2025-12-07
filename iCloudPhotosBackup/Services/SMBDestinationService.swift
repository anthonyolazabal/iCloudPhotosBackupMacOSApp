import Foundation
import NetFS
import OSLog
import CryptoKit

/// Service for backing up photos to SMB network shares
class SMBDestinationService: BackupDestination {
    let id: UUID
    let name: String
    let type: DestinationType = .smb

    private let configuration: SMBConfiguration
    private var mountPoint: URL?
    private var isMounted: Bool = false
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "SMBDestination")
    private let fileManager = FileManager.default

    // MARK: - Initialization

    init(configuration: SMBConfiguration) throws {
        try configuration.validate()

        self.id = configuration.id
        self.name = configuration.name
        self.configuration = configuration
    }

    // MARK: - BackupDestination Protocol

    func connect() async throws {
        guard !isMounted else {
            logger.info("Already mounted to SMB share")
            return
        }

        // Build SMB URL without credentials (credentials passed separately)
        guard let smbURL = buildMountURL() else {
            throw DestinationError.invalidConfiguration(reason: "Invalid SMB URL")
        }

        logger.info("Connecting to SMB share: \(self.configuration.displayURL)")
        logger.info("SMB URL: \(smbURL.absoluteString)")

        // Prepare open options
        let openOptions = NSMutableDictionary()

        // Prepare mount options
        let mountOptions = NSMutableDictionary()
        mountOptions[kNetFSSoftMountKey] = true

        // Get credentials
        let username: CFString?
        let password: CFString?

        if configuration.authType == .credentials && !configuration.username.isEmpty {
            // Include domain in username if provided
            if !configuration.domain.isEmpty {
                username = "\(configuration.domain);\(configuration.username)" as CFString
            } else {
                username = configuration.username as CFString
            }
            password = configuration.password as CFString
            logger.info("Using credentials for user: \(self.configuration.username)")
        } else {
            username = "guest" as CFString
            password = "" as CFString
            openOptions[kNetFSUseGuestKey] = true
            logger.info("Using guest authentication")
        }

        // Perform mount operation - let the system choose the mount point
        let mountResult: (Int32, URL?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var mountPoints: Unmanaged<CFArray>?

                let status = NetFSMountURLSync(
                    smbURL as CFURL,
                    nil,  // Let system choose mount point
                    username,
                    password,
                    openOptions,
                    mountOptions,
                    &mountPoints
                )

                // Get the actual mount point from the result
                var resultMountPoint: URL? = nil
                if status == 0, let mountPointsArray = mountPoints?.takeRetainedValue() as? [String],
                   let firstMount = mountPointsArray.first {
                    resultMountPoint = URL(fileURLWithPath: firstMount)
                }

                continuation.resume(returning: (status, resultMountPoint))
            }
        }

        guard mountResult.0 == 0 else {
            let errorMessage = describeNetFSError(mountResult.0)
            logger.error("Failed to mount SMB share: \(errorMessage)")
            throw SMBError.mountFailed(errorCode: mountResult.0)
        }

        // Use the mount point returned by the system, or construct one based on share name
        if let systemMountPoint = mountResult.1 {
            self.mountPoint = systemMountPoint
        } else {
            // Fallback: construct expected mount point path based on share name
            let shareName = configuration.shareName
            let expectedMountPath = "/Volumes/\(shareName)"
            self.mountPoint = URL(fileURLWithPath: expectedMountPath)
        }

        self.isMounted = true
        logger.info("Successfully mounted SMB share at \(self.mountPoint?.path ?? "unknown")")

        // Verify the mount and path prefix exist
        let targetPath = buildLocalPath(for: "")
        if !fileManager.fileExists(atPath: targetPath) {
            // Create the path prefix directory if it doesn't exist
            try fileManager.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
            logger.info("Created path prefix directory: \(self.configuration.pathPrefix)")
        }
    }

    /// Build SMB URL without credentials (credentials are passed separately)
    private func buildMountURL() -> URL? {
        var urlString = "smb://\(configuration.serverAddress)"

        // Add port if non-standard
        if configuration.port != 445 {
            urlString += ":\(configuration.port)"
        }

        // Add share name
        let escapedShare = configuration.shareName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? configuration.shareName
        urlString += "/\(escapedShare)"

        return URL(string: urlString)
    }

    /// Describe NetFS error codes
    private func describeNetFSError(_ code: Int32) -> String {
        switch code {
        case 0:
            return "Success"
        case 1:
            return "Generic error - check server address, share name, and credentials"
        case 2:
            return "No such file or directory - share may not exist"
        case 13:
            return "Permission denied - check credentials"
        case 22:
            return "Invalid argument - check URL format"
        case 51:
            return "Network unreachable - check network connection"
        case 60:
            return "Operation timed out - server may be unreachable"
        case 61:
            return "Connection refused - check if SMB service is running"
        case 64:
            return "Host is down"
        case 65:
            return "No route to host"
        case -6600:
            return "Authentication failed - check username and password"
        case -6602:
            return "Share does not exist"
        case -6003:
            return "Server not found"
        default:
            return "Error code \(code)"
        }
    }

    func disconnect() async throws {
        guard isMounted, let mountPoint = mountPoint else {
            logger.info("Not mounted, nothing to disconnect")
            return
        }

        logger.info("Disconnecting from SMB share")

        // Use POSIX unmount - try soft unmount first
        var unmountResult = Darwin.unmount(mountPoint.path, 0)

        // If soft unmount fails, try force unmount
        if unmountResult != 0 {
            logger.warning("Soft unmount failed, attempting force unmount")
            unmountResult = Darwin.unmount(mountPoint.path, MNT_FORCE)
            if unmountResult != 0 {
                logger.error("Force unmount failed with error: \(unmountResult)")
            }
        }

        // Note: Don't try to remove the mount point directory as it's managed by the system

        self.mountPoint = nil
        self.isMounted = false
        logger.info("Disconnected from SMB share")
    }

    func upload(file: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws -> UploadResult {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let startTime = Date()
        let localDestinationPath = buildLocalPath(for: remotePath)
        let destinationURL = URL(fileURLWithPath: localDestinationPath)

        // Create directory structure if needed
        let destinationDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        // Get source file size for progress tracking
        let sourceAttributes = try fileManager.attributesOfItem(atPath: file.path)
        let fileSize = sourceAttributes[.size] as? Int64 ?? 0

        // Copy file with progress tracking
        let checksum = try await copyFileWithProgress(
            from: file,
            to: destinationURL,
            fileSize: fileSize,
            progress: progress
        )

        let duration = Date().timeIntervalSince(startTime)

        logger.info("Uploaded \(file.lastPathComponent) to \(remotePath) in \(String(format: "%.2f", duration))s")

        return UploadResult(
            remotePath: remotePath,
            checksum: checksum,
            size: fileSize,
            uploadDuration: duration
        )
    }

    func fileExists(at remotePath: String) async throws -> Bool {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: remotePath)
        return fileManager.fileExists(atPath: localPath)
    }

    func getFileMetadata(at remotePath: String) async throws -> RemoteFileMetadata? {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: remotePath)

        guard fileManager.fileExists(atPath: localPath) else {
            return nil
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: localPath)
            let size = attributes[.size] as? Int64 ?? 0
            let modifiedDate = attributes[.modificationDate] as? Date ?? Date()

            return RemoteFileMetadata(
                path: remotePath,
                size: size,
                modifiedDate: modifiedDate,
                checksum: nil  // Checksum calculated on demand
            )
        } catch {
            logger.error("Failed to get metadata for \(remotePath): \(error.localizedDescription)")
            return nil
        }
    }

    func listFiles(in directory: String) async throws -> [RemoteFileMetadata] {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: directory)
        var files: [RemoteFileMetadata] = []

        guard fileManager.fileExists(atPath: localPath) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: localPath),
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])

                guard resourceValues.isRegularFile == true else { continue }

                let size = Int64(resourceValues.fileSize ?? 0)
                let modifiedDate = resourceValues.contentModificationDate ?? Date()

                // Build relative path from the base directory
                let relativePath = fileURL.path.replacingOccurrences(
                    of: localPath,
                    with: directory
                )

                files.append(RemoteFileMetadata(
                    path: relativePath,
                    size: size,
                    modifiedDate: modifiedDate,
                    checksum: nil
                ))
            } catch {
                logger.warning("Failed to get attributes for \(fileURL.path): \(error.localizedDescription)")
            }
        }

        return files
    }

    func delete(at remotePath: String) async throws {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: remotePath)

        guard fileManager.fileExists(atPath: localPath) else {
            throw DestinationError.fileNotFound(remotePath: remotePath)
        }

        try fileManager.removeItem(atPath: localPath)
        logger.info("Deleted file: \(remotePath)")
    }

    func testConnection() async throws -> Bool {
        do {
            try await connect()

            // Test write permission by creating and deleting a test file
            let testFileName = ".icloudphotosbackup_test_\(UUID().uuidString)"
            let testPath = buildLocalPath(for: testFileName)
            let testData = "test".data(using: .utf8)!

            try testData.write(to: URL(fileURLWithPath: testPath))
            try fileManager.removeItem(atPath: testPath)

            try await disconnect()
            logger.info("Connection test successful")
            return true
        } catch {
            logger.error("Connection test failed: \(error.localizedDescription)")
            try? await disconnect()
            throw error
        }
    }

    func verifyChecksum(remotePath: String, expectedChecksum: String) async throws -> Bool {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: remotePath)

        guard fileManager.fileExists(atPath: localPath) else {
            return false
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        let hash = SHA256.hash(data: data)
        let actualChecksum = hash.compactMap { String(format: "%02x", $0) }.joined()

        return actualChecksum.lowercased() == expectedChecksum.lowercased()
    }

    func downloadFile(at remotePath: String, progress: @escaping (Double) -> Void) async throws -> Data {
        guard isMounted else {
            throw SMBError.notConnected
        }

        let localPath = buildLocalPath(for: remotePath)

        guard fileManager.fileExists(atPath: localPath) else {
            throw DestinationError.fileNotFound(remotePath: remotePath)
        }

        let fileURL = URL(fileURLWithPath: localPath)
        let attributes = try fileManager.attributesOfItem(atPath: localPath)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Read file in chunks with progress
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var data = Data()
        let chunkSize = 1024 * 1024  // 1 MB chunks
        var bytesRead: Int64 = 0

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            data.append(chunk)
            bytesRead += Int64(chunk.count)

            if fileSize > 0 {
                progress(Double(bytesRead) / Double(fileSize))
            }
        }

        progress(1.0)
        return data
    }

    // MARK: - Share Discovery

    /// Discover available shares on a server using smbutil
    static func discoverShares(
        server: String,
        username: String?,
        password: String?
    ) async throws -> [String] {
        // Build the smbutil view URL
        var urlString = "smb://"

        if let username = username, !username.isEmpty {
            urlString += username
            if let password = password, !password.isEmpty {
                urlString += ":\(password)"
            }
            urlString += "@"
        }

        urlString += server

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
                process.arguments = ["view", urlString]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    // Parse the smbutil output to extract share names
                    // Output format typically includes lines like:
                    // Share        Type      Comment
                    // -----        ----      -------
                    // ShareName    Disk
                    var shares: [String] = []
                    let lines = output.components(separatedBy: "\n")
                    var foundHeader = false

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)

                        // Skip empty lines
                        if trimmed.isEmpty { continue }

                        // Look for the separator line (----)
                        if trimmed.hasPrefix("----") {
                            foundHeader = true
                            continue
                        }

                        // After the header, extract share names
                        if foundHeader {
                            // Split by whitespace and get the first component (share name)
                            let components = trimmed.components(separatedBy: CharacterSet.whitespaces)
                                .filter { !$0.isEmpty }

                            if let shareName = components.first, !shareName.isEmpty {
                                // Filter out IPC$ and other system shares
                                if !shareName.hasSuffix("$") {
                                    shares.append(shareName)
                                }
                            }
                        }
                    }

                    continuation.resume(returning: shares)
                } catch {
                    continuation.resume(throwing: SMBError.shareDiscoveryFailed(errorCode: -1))
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func buildLocalPath(for remotePath: String) -> String {
        guard let mountPoint = mountPoint else {
            return ""
        }

        var path = mountPoint.path

        // Add path prefix
        if !configuration.pathPrefix.isEmpty {
            path += "/" + configuration.normalizedPathPrefix
        }

        // Add remote path
        if !remotePath.isEmpty {
            if !path.hasSuffix("/") && !remotePath.hasPrefix("/") {
                path += "/"
            }
            path += remotePath
        }

        return path
    }

    private func copyFileWithProgress(
        from source: URL,
        to destination: URL,
        fileSize: Int64,
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Remove destination if it exists
                    if self.fileManager.fileExists(atPath: destination.path) {
                        try self.fileManager.removeItem(at: destination)
                    }

                    // Open source file for reading
                    let sourceHandle = try FileHandle(forReadingFrom: source)
                    defer { try? sourceHandle.close() }

                    // Create destination file
                    self.fileManager.createFile(atPath: destination.path, contents: nil)
                    let destHandle = try FileHandle(forWritingTo: destination)
                    defer { try? destHandle.close() }

                    // Initialize SHA256 for checksum
                    var hasher = SHA256()
                    let chunkSize = 1024 * 1024  // 1 MB chunks
                    var bytesWritten: Int64 = 0

                    while let chunk = try sourceHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                        try destHandle.write(contentsOf: chunk)
                        hasher.update(data: chunk)
                        bytesWritten += Int64(chunk.count)

                        if fileSize > 0 {
                            progress(Double(bytesWritten) / Double(fileSize))
                        }
                    }

                    // Finalize checksum
                    let hash = hasher.finalize()
                    let checksum = hash.compactMap { String(format: "%02x", $0) }.joined()

                    progress(1.0)
                    continuation.resume(returning: checksum)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - SMB Errors

enum SMBError: Error, LocalizedError {
    case notConnected
    case mountFailed(errorCode: Int32)
    case unmountFailed(errorCode: Int32)
    case invalidServerAddress
    case shareDiscoveryFailed(errorCode: Int32)
    case writePermissionDenied
    case networkUnreachable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to SMB share"
        case .mountFailed(let code):
            return "Failed to mount SMB share: \(describeError(code))"
        case .unmountFailed(let code):
            return "Failed to unmount SMB share (error: \(code))"
        case .invalidServerAddress:
            return "Invalid server address"
        case .shareDiscoveryFailed(let code):
            return "Failed to discover shares (error: \(code))"
        case .writePermissionDenied:
            return "Write permission denied on SMB share"
        case .networkUnreachable:
            return "Network share is unreachable"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            return "Connect to the SMB share first"
        case .mountFailed(let code):
            return recoverySuggestionForCode(code)
        case .unmountFailed:
            return "Close any open files and try again"
        case .invalidServerAddress:
            return "Enter a valid server address or hostname"
        case .shareDiscoveryFailed:
            return "Check network connectivity and server availability"
        case .writePermissionDenied:
            return "Check share permissions for your user account"
        case .networkUnreachable:
            return "Check your network connection and ensure the server is online"
        }
    }

    private func describeError(_ code: Int32) -> String {
        switch code {
        case 1: return "Connection failed"
        case 2: return "Share not found"
        case 13: return "Permission denied"
        case 22: return "Invalid URL"
        case 51: return "Network unreachable"
        case 60: return "Connection timed out"
        case 61: return "Connection refused"
        case 64: return "Host is down"
        case 65: return "No route to host"
        case -6600: return "Authentication failed"
        case -6602: return "Share does not exist"
        case -6003: return "Server not found"
        default: return "Error \(code)"
        }
    }

    private func recoverySuggestionForCode(_ code: Int32) -> String {
        switch code {
        case 1:
            return "Verify the server address and share name are correct. Try connecting via Finder first (Go > Connect to Server)."
        case 2, -6602:
            return "The share name may be incorrect. Check the exact share name on your server."
        case 13:
            return "Check that your username and password are correct and have access to this share."
        case 51, 64, 65:
            return "Check your network connection and ensure the server is reachable."
        case 60:
            return "The server is taking too long to respond. Check if it's powered on and accessible."
        case 61:
            return "SMB service may not be running on the server. Verify SMB/CIFS is enabled."
        case -6600:
            return "Username or password is incorrect. If using a domain, try format: DOMAIN\\username"
        case -6003:
            return "Cannot find the server. Verify the hostname or IP address."
        default:
            return "Check server address, credentials, and network connectivity. Try connecting via Finder first."
        }
    }
}
