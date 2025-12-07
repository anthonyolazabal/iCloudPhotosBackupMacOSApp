// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iCloudPhotosBackup",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // AWS SDK for Swift (S3 support)
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "0.30.0"),

        // Keychain Access for secure credential storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),

        // GRDB for SQLite database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),

        // Swift Log for logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
    ],
    targets: []
)
