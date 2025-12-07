import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("iCloud Photos Backup")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 32) {
                    // App Info Card
                    VStack(spacing: 20) {
                        // App Icon
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.blue.opacity(0.1))
                            )

                        VStack(spacing: 8) {
                            Text("iCloud Photos Backup")
                                .font(.title)
                                .fontWeight(.bold)

                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text("A powerful macOS application for backing up your precious iCloud Photos to S3-compatible cloud storage or SMB network shares.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 500)
                    }
                    .padding(.vertical, 24)

                    Divider()
                        .frame(maxWidth: 400)

                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Key Features")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            FeatureItem(
                                icon: "lock.shield.fill",
                                title: "Secure Backups",
                                description: "Optional AES-256 encryption"
                            )
                            FeatureItem(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Smart Sync",
                                description: "Incremental backups with deduplication"
                            )
                            FeatureItem(
                                icon: "calendar.badge.clock",
                                title: "Scheduled Backups",
                                description: "Automated backup schedules"
                            )
                            FeatureItem(
                                icon: "checkmark.shield.fill",
                                title: "Verification",
                                description: "Integrity checks with checksums"
                            )
                            FeatureItem(
                                icon: "externaldrive.fill",
                                title: "Multiple Destinations",
                                description: "S3 and SMB support"
                            )
                            FeatureItem(
                                icon: "photo.stack.fill",
                                title: "Photo Browser",
                                description: "Browse and download backups"
                            )
                        }
                    }
                    .frame(maxWidth: 600)

                    Divider()
                        .frame(maxWidth: 400)

                    // Author Section
                    VStack(spacing: 16) {
                        Text("Created by")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.blue)

                            Text("Anthony Olazabal")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        Text("Anthony is a passionate developer and technology enthusiast who loves creating innovative solutions that make people's lives easier. With a deep curiosity for exploring new technologies and a drive to turn ideas into reality, he built iCloud Photos Backup to solve a real problem: giving users complete control over their photo backups. When he's not coding, Anthony enjoys experimenting with new frameworks, contributing to open-source projects, and finding creative ways to leverage technology. This app represents his belief that great software should be both powerful and accessible to everyone.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 550)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 16)

                    Divider()
                        .frame(maxWidth: 400)

                    // Technical Info
                    VStack(spacing: 12) {
                        Text("Technical Details")
                            .font(.headline)

                        VStack(spacing: 8) {
                            TechDetailRow(label: "Platform", value: "macOS 14.0+")
                            TechDetailRow(label: "Framework", value: "SwiftUI")
                            TechDetailRow(label: "Storage", value: "S3 Compatible, SMB/CIFS")
                            TechDetailRow(label: "Encryption", value: "AES-256-GCM")
                            TechDetailRow(label: "Database", value: "SQLite (GRDB)")
                        }
                        .frame(maxWidth: 300)
                    }

                    Divider()
                        .frame(maxWidth: 400)

                    // Privacy & Security
                    VStack(spacing: 12) {
                        Text("Privacy & Security")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Photos are read-only - never modified or deleted", systemImage: "hand.raised.fill")
                            Label("All data stays on your devices and chosen storage", systemImage: "lock.fill")
                            Label("No telemetry or analytics collected", systemImage: "eye.slash.fill")
                            Label("Open architecture - your data, your control", systemImage: "checkmark.shield.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    // Copyright
                    VStack(spacing: 4) {
                        Text("\u{00A9} 2025 Anthony Olazabal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text("Made with passion in France")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Feature Item

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Tech Detail Row

struct TechDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    AboutView()
        .frame(width: 800, height: 800)
}
