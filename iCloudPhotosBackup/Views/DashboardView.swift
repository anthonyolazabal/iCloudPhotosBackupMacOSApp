import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddDestination = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Overview of your photo backups")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if let progress = appState.currentSyncProgress {
                        SyncProgressIndicator(progress: progress)
                    }
                }
                .padding(.horizontal)

                // Statistics Cards
                if appState.destinations.isEmpty {
                    EmptyStateView(showingAddDestination: $showingAddDestination)
                } else {
                    StatsCardsView()
                    DestinationsOverview()
                    RecentActivityView()
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingAddDestination) {
            AddDestinationSheet()
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @Binding var showingAddDestination: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("No Destinations Configured")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add a destination to start backing up your photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                showingAddDestination = true
            }) {
                Label("Add Destination", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Stats Cards

struct StatsCardsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Total Photos",
                value: totalPhotos,
                icon: "photo.on.rectangle.angled",
                color: .blue
            )

            StatCard(
                title: "Storage Used",
                value: totalStorage,
                icon: "externaldrive",
                color: .green
            )

            StatCard(
                title: "Destinations",
                value: "\(appState.destinations.count)",
                icon: "server.rack",
                color: .orange
            )
        }
        .padding(.horizontal)
    }

    private var totalPhotos: String {
        let total = appState.stats.values.reduce(0) { $0 + $1.totalPhotos }
        return NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal)
    }

    private var totalStorage: String {
        let total = appState.stats.values.reduce(0) { $0 + $1.totalBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Destinations Overview

struct DestinationsOverview: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destinations")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(appState.destinations) { destination in
                    DestinationRow(destination: destination)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct DestinationRow: View {
    @Environment(AppState.self) private var appState
    let destination: DestinationRecord

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let stats = appState.stats[destination.id] {
                    Text("\(stats.totalPhotos) photos • \(stats.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Health indicator
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)

            // Sync button
            Button(action: {
                Task {
                    try? await appState.startSync(
                        destinationID: destination.id,
                        filter: .fullLibrary
                    )
                }
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var iconName: String {
        switch destination.type {
        case .s3: return "externaldrive.connected.to.line.below"
        case .smb: return "server.rack"
        case .sftp: return "network"
        case .ftp: return "arrow.up.doc"
        }
    }

    private var healthColor: Color {
        switch destination.healthStatus {
        case .healthy: return .green
        case .degraded: return .yellow
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Recent Activity

struct RecentActivityView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    // Navigate to history
                }
                .font(.caption)
            }
            .padding(.horizontal)

            if appState.recentJobs.isEmpty {
                Text("No recent sync jobs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.recentJobs.prefix(5)) { job in
                        JobRow(job: job)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct JobRow: View {
    @Environment(AppState.self) private var appState
    let job: SyncJob

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                if let dest = appState.destinations.first(where: { $0.id == job.destinationID }) {
                    Text(dest.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(job.photosSynced) photos")
                    .font(.caption)
                    .fontWeight(.medium)

                if job.photosFailed > 0 {
                    Text("\(job.photosFailed) failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch job.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .paused: return "pause.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .blue
        case .paused: return .orange
        case .cancelled: return .gray
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: job.startTime, relativeTo: Date())
    }
}

// MARK: - Sync Progress Indicator

struct SyncProgressIndicator: View {
    let progress: SyncProgress

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                ProgressView(value: progress.progress)
                    .frame(width: 100)

                Text("\(Int(progress.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            Text("\(progress.photosCompleted) of \(progress.totalPhotos)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DashboardView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
