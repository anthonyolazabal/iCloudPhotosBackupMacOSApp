import Foundation
@testable import iCloudPhotosBackup

/// Mock implementation of BackupDestination for testing
class MockBackupDestination: BackupDestination {
    let id: UUID
    let name: String
    let type: DestinationType = .s3

    // Mock data
    var mockFiles: [String: MockFile] = [:]
    var isConnected = false

    // Call tracking
    var connectCalled = false
    var disconnectCalled = false
    var uploadCalls: [(URL, String)] = []
    var fileExistsCalls: [String] = []
    var verifyChecksumCalls: [(String, String)] = []
    var deleteCalls: [String] = []

    // Error simulation
    var shouldFailConnect = false
    var shouldFailUpload = false
    var shouldFailVerify = false

    struct MockFile {
        let size: Int64
        let checksum: String
        let modifiedDate: Date
    }

    init(id: UUID = UUID(), name: String = "Mock Destination") {
        self.id = id
        self.name = name
    }

    func connect() async throws {
        connectCalled = true
        if shouldFailConnect {
            throw DestinationError.connectionFailed(reason: "Mock connection failed")
        }
        isConnected = true
    }

    func disconnect() async throws {
        disconnectCalled = true
        isConnected = false
    }

    func upload(file: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws -> UploadResult {
        uploadCalls.append((file, remotePath))

        if shouldFailUpload {
            throw DestinationError.uploadFailed(path: remotePath, underlying: nil)
        }

        // Simulate progress
        progress(0.5)
        progress(1.0)

        let fileSize = file.fileSize ?? 1000
        let checksum = "mock-checksum-\(UUID().uuidString.prefix(8))"

        // Add to mock files
        mockFiles[remotePath] = MockFile(
            size: fileSize,
            checksum: checksum,
            modifiedDate: Date()
        )

        return UploadResult(
            remotePath: remotePath,
            checksum: checksum,
            size: fileSize,
            uploadDuration: 1.0
        )
    }

    func fileExists(at remotePath: String) async throws -> Bool {
        fileExistsCalls.append(remotePath)
        return mockFiles[remotePath] != nil
    }

    func getFileMetadata(at remotePath: String) async throws -> RemoteFileMetadata? {
        guard let file = mockFiles[remotePath] else {
            return nil
        }

        return RemoteFileMetadata(
            path: remotePath,
            size: file.size,
            modifiedDate: file.modifiedDate,
            checksum: file.checksum
        )
    }

    func listFiles(in directory: String) async throws -> [RemoteFileMetadata] {
        return mockFiles
            .filter { $0.key.hasPrefix(directory) }
            .map { path, file in
                RemoteFileMetadata(
                    path: path,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    checksum: file.checksum
                )
            }
    }

    func delete(at remotePath: String) async throws {
        deleteCalls.append(remotePath)
        mockFiles.removeValue(forKey: remotePath)
    }

    func testConnection() async throws -> Bool {
        return !shouldFailConnect
    }

    func verifyChecksum(remotePath: String, expectedChecksum: String) async throws -> Bool {
        verifyChecksumCalls.append((remotePath, expectedChecksum))

        if shouldFailVerify {
            throw DestinationError.connectionFailed(reason: "Verification failed")
        }

        guard let file = mockFiles[remotePath] else {
            return false
        }

        return file.checksum == expectedChecksum
    }

    // MARK: - Helper Methods for Testing

    /// Add a mock file to the destination
    func addMockFile(path: String, checksum: String, size: Int64 = 1000) {
        mockFiles[path] = MockFile(
            size: size,
            checksum: checksum,
            modifiedDate: Date()
        )
    }

    /// Reset all call tracking
    func reset() {
        connectCalled = false
        disconnectCalled = false
        uploadCalls.removeAll()
        fileExistsCalls.removeAll()
        verifyChecksumCalls.removeAll()
        deleteCalls.removeAll()
        mockFiles.removeAll()
        shouldFailConnect = false
        shouldFailUpload = false
        shouldFailVerify = false
    }
}
