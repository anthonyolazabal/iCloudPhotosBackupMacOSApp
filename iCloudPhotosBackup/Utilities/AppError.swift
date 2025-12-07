import Foundation

// MARK: - App Error Protocol

protocol AppErrorProtocol: LocalizedError {
    var errorCategory: ErrorCategory { get }
    var recoverySuggestion: String? { get }
    var shouldRetry: Bool { get }
}

// MARK: - Error Category

enum ErrorCategory {
    case authentication
    case network
    case storage
    case photoLibrary
    case configuration
    case database
    case encryption
    case unknown
}

// MARK: - Photo Library Errors

enum PhotoLibraryError: AppErrorProtocol {
    case authorizationDenied
    case authorizationRestricted
    case fetchFailed(underlying: Error)
    case exportFailed(photoID: String, underlying: Error?)
    case iCloudDownloadFailed(photoID: String)
    case unsupportedAssetType(type: String)

    var errorCategory: ErrorCategory { .photoLibrary }

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Photo library access denied"
        case .authorizationRestricted:
            return "Photo library access is restricted"
        case .fetchFailed:
            return "Failed to fetch photos from library"
        case .exportFailed(let photoID, _):
            return "Failed to export photo: \(photoID)"
        case .iCloudDownloadFailed(let photoID):
            return "Failed to download photo from iCloud: \(photoID)"
        case .unsupportedAssetType(let type):
            return "Unsupported asset type: \(type)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authorizationDenied:
            return "Please grant photo library access in System Settings > Privacy & Security > Photos"
        case .authorizationRestricted:
            return "Photo library access is restricted. Contact your system administrator."
        case .fetchFailed:
            return "Try restarting the app or check your photo library"
        case .exportFailed:
            return "This photo may be corrupted or unavailable. Sync will continue with other photos."
        case .iCloudDownloadFailed:
            return "Ensure you have an active internet connection and enough iCloud storage"
        case .unsupportedAssetType:
            return "This asset type is not yet supported for backup"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .iCloudDownloadFailed, .exportFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Destination Errors

enum DestinationError: AppErrorProtocol {
    case connectionFailed(underlying: Error?)
    case authenticationFailed
    case uploadFailed(remotePath: String, underlying: Error?)
    case quotaExceeded
    case fileNotFound(remotePath: String)
    case invalidConfiguration(reason: String)
    case checksumMismatch(remotePath: String)

    var errorCategory: ErrorCategory {
        switch self {
        case .authenticationFailed:
            return .authentication
        case .connectionFailed, .uploadFailed:
            return .network
        case .quotaExceeded:
            return .storage
        case .invalidConfiguration:
            return .configuration
        default:
            return .unknown
        }
    }

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to destination"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        case .uploadFailed(let remotePath, _):
            return "Failed to upload file to: \(remotePath)"
        case .quotaExceeded:
            return "Storage quota exceeded"
        case .fileNotFound(let remotePath):
            return "File not found: \(remotePath)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .checksumMismatch(let remotePath):
            return "Checksum verification failed for: \(remotePath)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check your internet connection and destination settings"
        case .authenticationFailed:
            return "Verify your access credentials in destination settings"
        case .uploadFailed:
            return "Check your network connection and try again"
        case .quotaExceeded:
            return "Free up space on your destination or upgrade your storage plan"
        case .fileNotFound:
            return "The file may have been deleted from the destination"
        case .invalidConfiguration:
            return "Review and correct your destination configuration"
        case .checksumMismatch:
            return "The uploaded file appears to be corrupted. It will be re-uploaded."
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .uploadFailed, .connectionFailed, .checksumMismatch:
            return true
        default:
            return false
        }
    }
}

// MARK: - Database Errors

enum DatabaseError: AppErrorProtocol {
    case initializationFailed(underlying: Error)
    case queryFailed(query: String, underlying: Error)
    case corruptedDatabase
    case migrationFailed(fromVersion: Int, toVersion: Int)

    var errorCategory: ErrorCategory { .database }

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize database"
        case .queryFailed(let query, _):
            return "Database query failed: \(query)"
        case .corruptedDatabase:
            return "Database is corrupted"
        case .migrationFailed(let from, let to):
            return "Database migration failed (v\(from) → v\(to))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .initializationFailed:
            return "Try restarting the app. If the problem persists, contact support."
        case .queryFailed:
            return "This may be a temporary issue. Try again."
        case .corruptedDatabase:
            return "Your database may need to be restored from a backup"
        case .migrationFailed:
            return "App update failed. Try reinstalling the app."
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .queryFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Encryption Errors

enum EncryptionError: AppErrorProtocol {
    case encryptionFailed(reason: String)
    case decryptionFailed(reason: String)
    case invalidPassphrase(reason: String)
    case keyGenerationFailed(reason: String)
    case keyNotFound
    case invalidKeyData
    case keychainError(status: OSStatus)

    var errorCategory: ErrorCategory { .encryption }

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .invalidPassphrase(let reason):
            return "Invalid passphrase: \(reason)"
        case .keyGenerationFailed(let reason):
            return "Key generation failed: \(reason)"
        case .keyNotFound:
            return "Encryption key not found"
        case .invalidKeyData:
            return "Invalid encryption key data"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .encryptionFailed, .decryptionFailed:
            return "This file may be corrupted. Try again or skip this file."
        case .invalidPassphrase:
            return "Please enter a valid passphrase (minimum 12 characters)"
        case .keyGenerationFailed:
            return "Try restarting the app"
        case .keyNotFound:
            return "Set up encryption with a passphrase in Settings"
        case .invalidKeyData:
            return "Your encryption key may be corrupted. Set up encryption again."
        case .keychainError:
            return "Check System Settings > Privacy & Security > Keychain Access"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .encryptionFailed, .decryptionFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sync Errors

enum SyncError: AppErrorProtocol {
    case alreadyRunning
    case notRunning
    case cancelled
    case noPhotosToSync
    case partialFailure(successCount: Int, failureCount: Int)

    var errorCategory: ErrorCategory { .unknown }

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A sync operation is already running"
        case .notRunning:
            return "No sync operation is running"
        case .cancelled:
            return "Sync operation was cancelled"
        case .noPhotosToSync:
            return "No photos found to sync"
        case .partialFailure(let success, let failure):
            return "Sync completed with errors: \(success) succeeded, \(failure) failed"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .alreadyRunning:
            return "Wait for the current sync to complete or cancel it first"
        case .notRunning:
            return "Start a sync operation first"
        case .cancelled:
            return "Resume the sync or start a new one"
        case .noPhotosToSync:
            return "Adjust your date range filter or check your photo library"
        case .partialFailure:
            return "Review the error log and retry failed photos from History"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .partialFailure:
            return true
        default:
            return false
        }
    }
}

// MARK: - Validation Error

enum ValidationError: AppErrorProtocol {
    case emptyField(fieldName: String)
    case invalidURL(url: String)
    case invalidCredentials
    case invalidFormat(fieldName: String, expectedFormat: String)

    var errorCategory: ErrorCategory { .configuration }

    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) cannot be empty"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidCredentials:
            return "Invalid credentials format"
        case .invalidFormat(let field, let format):
            return "\(field) has invalid format. Expected: \(format)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyField:
            return "Please fill in all required fields"
        case .invalidURL:
            return "Enter a valid URL (e.g., https://example.com)"
        case .invalidCredentials:
            return "Check your access key and secret key format"
        case .invalidFormat:
            return "Correct the field format and try again"
        }
    }

    var shouldRetry: Bool { false }
}
