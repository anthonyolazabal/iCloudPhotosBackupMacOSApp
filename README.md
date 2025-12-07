# iCloud Photos Backup

A macOS application that backs up photos from iCloud Photos to cloud storage (S3, SMB, SFTP, FTP). The app runs in the background, supports scheduled syncs, and provides a simple monitoring UI.

## Features

- **Read-Only Photo Access**: Never modifies your iCloud Photos library
- **Client-Side Encryption**: Optional AES-256 encryption before upload
- **Multiple Destinations**: Support for S3-compatible storage (AWS, Minio, OVH, Backblaze B2, Wasabi)
- **Smart Deduplication**: Avoids uploading photos that already exist
- **Scheduled Backups**: Automatic background syncs on your schedule
- **Verification Mode**: Verify backup integrity without uploading
- **Format Conversion**: Optional HEIC → JPEG conversion for compatibility
- **Progress Tracking**: Real-time sync progress with speed and time estimates

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for development)
- Swift 5.9 or later

## Architecture

This application follows MVVM architecture with the following key components:

### Core Protocols

- **PhotoSource**: Read-only interface for accessing iCloud Photos via PhotoKit
- **BackupDestination**: Abstract interface for upload destinations (S3, SMB, SFTP, FTP)
- **SyncEngine**: Orchestrates backup operations between source and destination

### Key Design Principles

1. **Read-Only Photo Access**: The app NEVER modifies your photo library. While we request `.readWrite` permission (required by Apple), we only use read/export APIs.

2. **Privacy First**: Optional client-side encryption ensures your photos are encrypted before leaving your Mac.

3. **Robust Error Handling**: Comprehensive error types with recovery suggestions and retry policies.

4. **Performance**: Batch processing, streaming, and memory management for large libraries (50,000+ photos).

## Project Structure

```
iCloudPhotosBackup/
├── Models/              # Data models
├── Views/               # SwiftUI views
├── Services/            # Core services (PhotoKit, S3, Sync Engine)
├── Utilities/           # Helpers and error types
└── Resources/           # Assets and localizations
```

## Getting Started

### Development Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd iCloudPhotosSync
   ```

2. Open in Xcode:
   ```bash
   open iCloudPhotosBackup.xcodeproj
   ```

3. Build and run (⌘R)

### Dependencies

Dependencies are managed via Swift Package Manager:

- **AWS SDK for Swift**: S3 storage support
- **KeychainAccess**: Secure credential storage
- **GRDB**: SQLite database for sync state
- **SwiftLog**: Logging framework

## Security

### Read-Only Compliance

This app is designed to NEVER modify your photo library. We enforce this through:

- Code review checklist for prohibited APIs
- CI checks to detect write operations
- Clear architectural constraints

### Prohibited APIs

The following PhotoKit APIs are NEVER used:
- `PHAssetChangeRequest`
- `PHAssetCollectionChangeRequest`
- `PHAssetCreationRequest`
- `PHPhotoLibrary.shared().performChanges()`

### Encryption

Optional client-side encryption uses:
- AES-256 for file encryption
- PBKDF2 for key derivation from passphrase
- Keychain Services for secure key storage

## Development Status

Currently implementing **Phase 1: Project Setup & Foundation**

See [icloud-photos-backup-plan.md](icloud-photos-backup-plan.md) for the complete development roadmap.

### Completed
- ✅ Project structure and Xcode configuration
- ✅ Entitlements and Info.plist setup
- ✅ Base architecture protocols (PhotoSource, BackupDestination, SyncEngine)
- ✅ Comprehensive error type system
- ✅ Basic UI structure with navigation

### In Progress
- 🔄 PhotoKit integration
- 🔄 S3 destination implementation
- 🔄 Local database setup

### Upcoming
- ⏳ Deduplication system
- ⏳ Sync engine implementation
- ⏳ Client-side encryption
- ⏳ Background scheduling

## Contributing

This is currently a personal project. Contributions and feedback are welcome once the MVP is complete.

## License

TBD

## Privacy & Data Handling

- **Photo Library**: Read-only access. Your photos are never modified.
- **Credentials**: Stored securely in macOS Keychain.
- **Telemetry**: Optional, opt-in only. No data collected by default.
- **No Cloud Dependencies**: App works completely offline once configured (except for uploads).

## Support

For issues and questions, please check the [troubleshooting guide](docs/troubleshooting.md) (coming soon) or open an issue.

---

**Important**: This app only reads your photos for backup purposes. Your photo library is never modified.
