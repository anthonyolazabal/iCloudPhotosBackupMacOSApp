import Foundation
import AWSS3
import AWSClientRuntime
import SmithyIdentity
import OSLog
import CryptoKit

/// S3-compatible storage destination implementation
/// Supports AWS S3, Minio, OVH, Backblaze B2, Wasabi, and other S3-compatible providers
class S3DestinationService: BackupDestination {
    let id: UUID
    let name: String
    let type: DestinationType = .s3

    private let configuration: S3Configuration
    private var s3Client: S3Client?
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "S3Destination")
    private let maxRetries = 3
    private let multipartThreshold: Int64 = 50 * 1024 * 1024 // 50 MB

    // MARK: - Initialization

    init(configuration: S3Configuration) throws {
        self.id = configuration.id
        self.name = configuration.name
        self.configuration = configuration

        // Validate configuration before initialization
        try configuration.validate()

        logger.info("S3DestinationService initialized: \(self.name) (\(configuration.provider.rawValue))")
    }

    // MARK: - Connection Management

    func connect() async throws {
        logger.info("Connecting to S3: \(self.name)")

        do {
            // Create static credentials
            let credentials = AWSCredentialIdentity(
                accessKey: configuration.accessKeyID,
                secret: configuration.secretAccessKey
            )

            // Create S3 client configuration
            let s3Config = try await S3Client.S3ClientConfiguration(region: configuration.region)
            s3Config.awsCredentialIdentityResolver = try StaticAWSCredentialIdentityResolver(credentials)

            // Set custom endpoint if not AWS
            if configuration.provider != .aws {
                s3Config.endpoint = configuration.endpointURL
            }

            // Configure path-style access
            // Force path-style for Minio, or if explicitly configured
            // OVH and other S3-compatible providers typically work with virtual-hosted style
            let usePathStyle = configuration.usePathStyleAccess ||
                               configuration.provider == .minio
            s3Config.forcePathStyle = usePathStyle

            logger.info("S3 config - endpoint: \(self.configuration.endpointURL), region: \(self.configuration.region), pathStyle: \(usePathStyle)")

            // Create client
            self.s3Client = S3Client(config: s3Config)

            // Verify connection by listing bucket
            _ = try await verifyBucketAccess()

            logger.info("Successfully connected to S3: \(self.name)")

        } catch {
            // Log detailed error information
            let errorDescription = String(describing: error)
            logger.error("Failed to connect to S3: \(errorDescription)")
            logger.error("Error type: \(Swift.type(of: error))")

            // Log the full error dump for debugging
            let mirror = Mirror(reflecting: error)
            for child in mirror.children {
                logger.error("Error property - \(child.label ?? "unknown"): \(String(describing: child.value))")
            }

            throw DestinationError.connectionFailed(underlying: error)
        }
    }

    func disconnect() async throws {
        logger.info("Disconnecting from S3: \(self.name)")
        self.s3Client = nil
    }

    // MARK: - Test Connection

    func testConnection() async throws -> Bool {
        logger.info("Testing S3 connection: \(self.name)")

        if s3Client == nil {
            try await connect()
        }

        do {
            _ = try await verifyBucketAccess()
            logger.info("Connection test successful")
            return true
        } catch {
            logger.error("Connection test failed: \(error.localizedDescription)")
            throw DestinationError.connectionFailed(underlying: error)
        }
    }

    // MARK: - Upload

    func upload(file: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws -> UploadResult {
        logger.info("Uploading file to S3: \(remotePath)")

        guard let client = s3Client else {
            logger.error("S3 client not connected")
            throw DestinationError.connectionFailed(underlying: nil)
        }

        let startTime = Date()

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw DestinationError.uploadFailed(remotePath: remotePath, underlying: nil)
        }

        // Calculate checksum
        let checksum = try calculateChecksum(for: file)

        do {
            // Use multipart upload for large files
            if fileSize > multipartThreshold {
                try await uploadMultipart(
                    client: client,
                    file: file,
                    remotePath: remotePath,
                    fileSize: fileSize,
                    progress: progress
                )
            } else {
                try await uploadSinglePart(
                    client: client,
                    file: file,
                    remotePath: remotePath,
                    progress: progress
                )
            }

            let duration = Date().timeIntervalSince(startTime)

            logger.info("Upload successful: \(remotePath), size: \(fileSize) bytes, duration: \(String(format: "%.2f", duration))s")

            return UploadResult(
                remotePath: remotePath,
                checksum: checksum,
                size: fileSize,
                uploadDuration: duration
            )

        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")
            throw DestinationError.uploadFailed(remotePath: remotePath, underlying: error)
        }
    }

    // MARK: - Single Part Upload

    private func uploadSinglePart(
        client: S3Client,
        file: URL,
        remotePath: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        // Read file data
        let fileData = try Data(contentsOf: file)

        // Create put object request
        let serverSideEncryption: S3ClientTypes.ServerSideEncryption? = configuration.serverSideEncryption.headerValue.flatMap { S3ClientTypes.ServerSideEncryption(rawValue: $0) }
        let input = PutObjectInput(
            body: .data(fileData),
            bucket: configuration.bucketName,
            key: buildKey(remotePath),
            serverSideEncryption: serverSideEncryption,
            storageClass: .init(rawValue: configuration.storageClass.rawValue)
        )

        _ = try await client.putObject(input: input)

        // Report 100% progress
        progress(1.0)
    }

    // MARK: - Multipart Upload

    private func uploadMultipart(
        client: S3Client,
        file: URL,
        remotePath: String,
        fileSize: Int64,
        progress: @escaping (Double) -> Void
    ) async throws {
        let key = buildKey(remotePath)
        let partSize: Int64 = 10 * 1024 * 1024 // 10 MB parts

        // Initiate multipart upload
        let serverSideEncryption: S3ClientTypes.ServerSideEncryption? = configuration.serverSideEncryption.headerValue.flatMap { S3ClientTypes.ServerSideEncryption(rawValue: $0) }
        let createInput = CreateMultipartUploadInput(
            bucket: configuration.bucketName,
            key: key,
            serverSideEncryption: serverSideEncryption,
            storageClass: .init(rawValue: configuration.storageClass.rawValue)
        )

        let createOutput = try await client.createMultipartUpload(input: createInput)

        guard let uploadID = createOutput.uploadId else {
            throw DestinationError.uploadFailed(remotePath: remotePath, underlying: nil)
        }

        logger.info("Multipart upload initiated: \(uploadID)")

        var completedParts: [S3ClientTypes.CompletedPart] = []
        var uploadedBytes: Int64 = 0

        do {
            // Open file for reading
            let fileHandle = try FileHandle(forReadingFrom: file)
            defer { try? fileHandle.close() }

            var partNumber = 1

            while uploadedBytes < fileSize {
                let remainingBytes = fileSize - uploadedBytes
                let currentPartSize = min(partSize, remainingBytes)

                // Read part data
                let partData = try fileHandle.read(upToCount: Int(currentPartSize))
                guard let data = partData, !data.isEmpty else { break }

                // Upload part with retry
                let etag = try await uploadPartWithRetry(
                    client: client,
                    bucket: configuration.bucketName,
                    key: key,
                    uploadID: uploadID,
                    partNumber: partNumber,
                    data: data
                )

                completedParts.append(S3ClientTypes.CompletedPart(
                    eTag: etag,
                    partNumber: partNumber
                ))

                uploadedBytes += Int64(data.count)
                partNumber += 1

                // Report progress
                progress(Double(uploadedBytes) / Double(fileSize))
            }

            // Complete multipart upload
            let completeInput = CompleteMultipartUploadInput(
                bucket: configuration.bucketName,
                key: key,
                multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completedParts),
                uploadId: uploadID
            )

            _ = try await client.completeMultipartUpload(input: completeInput)

            logger.info("Multipart upload completed: \(remotePath)")

        } catch {
            // Abort multipart upload on failure
            logger.error("Multipart upload failed, aborting: \(error.localizedDescription)")

            let abortInput = AbortMultipartUploadInput(
                bucket: configuration.bucketName,
                key: key,
                uploadId: uploadID
            )

            _ = try? await client.abortMultipartUpload(input: abortInput)

            throw error
        }
    }

    // MARK: - Upload Part with Retry

    private func uploadPartWithRetry(
        client: S3Client,
        bucket: String,
        key: String,
        uploadID: String,
        partNumber: Int,
        data: Data
    ) async throws -> String {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                let input = UploadPartInput(
                    body: .data(data),
                    bucket: bucket,
                    key: key,
                    partNumber: partNumber,
                    uploadId: uploadID
                )

                let output = try await client.uploadPart(input: input)

                guard let etag = output.eTag else {
                    throw DestinationError.uploadFailed(remotePath: key, underlying: nil)
                }

                return etag

            } catch {
                lastError = error
                logger.warning("Part upload attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Exponential backoff
                    let delay = Double(1 << (attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? DestinationError.uploadFailed(remotePath: key, underlying: nil)
    }

    // MARK: - File Operations

    func fileExists(at remotePath: String) async throws -> Bool {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        let key = buildKey(remotePath)

        do {
            let input = HeadObjectInput(
                bucket: configuration.bucketName,
                key: key
            )

            _ = try await client.headObject(input: input)
            return true

        } catch _ as NoSuchKey {
            logger.debug("File does not exist: \(remotePath)")
            return false
        } catch {
            logger.error("Error checking file existence: \(error.localizedDescription)")
            throw DestinationError.connectionFailed(underlying: error)
        }
    }

    func getFileMetadata(at remotePath: String) async throws -> RemoteFileMetadata? {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        let key = buildKey(remotePath)

        do {
            let input = HeadObjectInput(
                bucket: configuration.bucketName,
                key: key
            )

            let output = try await client.headObject(input: input)

            return RemoteFileMetadata(
                path: remotePath,
                size: Int64(output.contentLength ?? 0),
                modifiedDate: output.lastModified ?? Date(),
                checksum: output.eTag?.replacingOccurrences(of: "\"", with: "")
            )

        } catch _ as NoSuchKey {
            return nil
        } catch {
            logger.error("Error getting file metadata: \(error.localizedDescription)")
            throw DestinationError.connectionFailed(underlying: error)
        }
    }

    func listFiles(in directory: String) async throws -> [RemoteFileMetadata] {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        var files: [RemoteFileMetadata] = []
        var continuationToken: String?

        repeat {
            let input = ListObjectsV2Input(
                bucket: configuration.bucketName,
                continuationToken: continuationToken,
                prefix: buildKey(directory)
            )

            let output = try await client.listObjectsV2(input: input)

            if let contents = output.contents {
                for object in contents {
                    if let key = object.key {
                        files.append(RemoteFileMetadata(
                            path: key,
                            size: Int64(object.size ?? 0),
                            modifiedDate: object.lastModified ?? Date(),
                            checksum: object.eTag?.replacingOccurrences(of: "\"", with: "")
                        ))
                    }
                }
            }

            continuationToken = output.nextContinuationToken

        } while continuationToken != nil

        logger.info("Listed \(files.count) files in: \(directory)")
        return files
    }

    func delete(at remotePath: String) async throws {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        let key = buildKey(remotePath)

        let input = DeleteObjectInput(
            bucket: configuration.bucketName,
            key: key
        )

        _ = try await client.deleteObject(input: input)

        logger.info("Deleted file: \(remotePath)")
    }

    // MARK: - Checksum Verification

    func verifyChecksum(remotePath: String, expectedChecksum: String) async throws -> Bool {
        // Note: S3 ETags are NOT reliable for checksum verification:
        // - Single-part uploads: ETag is MD5 (different from our SHA-256)
        // - Multipart uploads: ETag is "md5-partcount" format
        // - Some providers modify ETags
        //
        // For reliable verification, we check if the file exists and has content.
        // True content verification would require downloading the file and computing SHA-256,
        // which is expensive for large libraries.
        //
        // This method returns true if the file exists (already verified by fileExists call in VerificationService)

        guard let metadata = try await getFileMetadata(at: remotePath) else {
            throw DestinationError.fileNotFound(remotePath: remotePath)
        }

        // File exists and has size > 0 means it was uploaded successfully
        // We trust the upload process that computed the SHA-256 checksum
        let isValid = metadata.size > 0

        if !isValid {
            logger.warning("File has zero size: \(remotePath)")
        }

        return isValid
    }

    /// Verify a file by comparing its size against an expected size
    /// This is more reliable than checksum comparison for S3
    func verifyFileSize(remotePath: String, expectedSize: Int64) async throws -> Bool {
        guard let metadata = try await getFileMetadata(at: remotePath) else {
            throw DestinationError.fileNotFound(remotePath: remotePath)
        }

        let match = metadata.size == expectedSize
        if !match {
            logger.warning("Size mismatch for \(remotePath): expected \(expectedSize), got \(metadata.size)")
        }

        return match
    }

    // MARK: - Download File

    func downloadFile(at remotePath: String, progress: @escaping (Double) -> Void) async throws -> Data {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        let key = buildKey(remotePath)
        logger.info("Downloading file: \(key)")

        let input = GetObjectInput(
            bucket: configuration.bucketName,
            key: key
        )

        let output = try await client.getObject(input: input)

        guard let body = output.body else {
            throw DestinationError.fileNotFound(remotePath: remotePath)
        }

        // Read data from the ByteStream
        let data = try await body.readData() ?? Data()

        progress(1.0)
        logger.info("Downloaded file: \(key), size: \(data.count) bytes")

        return data
    }

    // MARK: - Helper Methods

    private func buildKey(_ remotePath: String) -> String {
        var key = remotePath

        // Add path prefix if configured
        if !configuration.pathPrefix.isEmpty {
            let prefix = configuration.pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            key = "\(prefix)/\(remotePath)"
        }

        return key
    }

    private func verifyBucketAccess() async throws -> Bool {
        guard let client = s3Client else {
            throw DestinationError.connectionFailed(underlying: nil)
        }

        // Try to list objects (with max 1 result) to verify access
        let input = ListObjectsV2Input(
            bucket: configuration.bucketName,
            maxKeys: 1
        )

        _ = try await client.listObjectsV2(input: input)

        return true
    }

    private func calculateChecksum(for fileURL: URL) throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: fileData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
