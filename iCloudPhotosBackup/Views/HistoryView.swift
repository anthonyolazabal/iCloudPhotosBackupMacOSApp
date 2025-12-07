import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0
    @State private var showingClearAllAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("View past sync and verification operations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if (selectedTab == 0 && !appState.recentJobs.isEmpty) ||
                   (selectedTab == 1 && !appState.recentVerificationJobs.isEmpty) {
                    Button(action: { showingClearAllAlert = true }) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()

            // Tab Picker
            Picker("History Type", selection: $selectedTab) {
                Text("Sync Jobs").tag(0)
                Text("Verifications").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom)

            Divider()

            // Content based on selected tab
            if selectedTab == 0 {
                // Sync Jobs List
                if appState.recentJobs.isEmpty {
                    EmptyHistoryView()
                } else {
                    SyncJobsHistoryList()
                }
            } else {
                // Verification History
                if !appState.recentVerificationJobs.isEmpty {
                    VerificationHistoryList()
                } else {
                    EmptyVerificationHistoryView()
                }
            }
        }
        .alert("Clear All History", isPresented: $showingClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task {
                    if selectedTab == 0 {
                        await appState.deleteAllSyncJobs()
                    } else {
                        await appState.deleteAllVerificationJobs()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all \(selectedTab == 0 ? "sync" : "verification") history? This action cannot be undone.")
        }
        .task {
            await appState.loadRecentJobs()
            await appState.loadRecentVerificationJobs()
        }
    }
}

// MARK: - Sync Jobs History List

struct SyncJobsHistoryList: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.recentJobs) { job in
            HistoryJobRow(job: job)
        }
    }
}

// MARK: - Verification History List

struct VerificationHistoryList: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.recentVerificationJobs) { job in
            VerificationJobRow(job: job)
        }
    }
}

// MARK: - Verification Job Row (from database)

struct VerificationJobRow: View {
    @Environment(AppState.self) private var appState
    let job: VerificationJob
    @State private var isExpanded = false
    @State private var showingDeleteAlert = false
    @State private var showingLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Status Icon
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .frame(width: 30)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let dest = appState.destinations.first(where: { $0.id == job.destinationID }) {
                            Text("Verification: \(dest.name)")
                                .font(.headline)
                        } else {
                            Text("Verification")
                                .font(.headline)
                        }

                        Text("(\(job.type.rawValue.capitalized))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let endTime = job.endTime {
                        Text(endTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(job.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Stats
                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(job.verifiedCount)/\(job.totalPhotos)", systemImage: "checkmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    if job.mismatchCount > 0 || job.missingCount > 0 {
                        Label("\(job.mismatchCount + job.missingCount) issues", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button(action: { showingLogs = true }) {
                            Label("View Logs", systemImage: "doc.text")
                        }
                        Divider()
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }

            // Expanded Details
            if isExpanded {
                Divider()

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    DetailItem(label: "Started", value: job.startTime.formatted(date: .omitted, time: .shortened))
                    if let endTime = job.endTime {
                        DetailItem(label: "Ended", value: endTime.formatted(date: .omitted, time: .shortened))
                        DetailItem(label: "Duration", value: formatDuration(job.startTime, endTime))
                    }
                    DetailItem(label: "Type", value: job.type.rawValue.capitalized)
                    DetailItem(label: "Total Photos", value: "\(job.totalPhotos)")
                    DetailItem(label: "Verified", value: "\(job.verifiedCount)")
                    DetailItem(label: "Mismatches", value: "\(job.mismatchCount)")
                    DetailItem(label: "Missing", value: "\(job.missingCount)")
                    DetailItem(label: "Errors", value: "\(job.errorCount)")
                    DetailItem(label: "Success Rate", value: String(format: "%.1f%%", job.successRate * 100))
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
        .alert("Delete Verification", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteVerificationJob(id: job.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this verification job from history?")
        }
        .sheet(isPresented: $showingLogs) {
            VerificationJobLogsView(job: job)
        }
    }

    private var statusIcon: String {
        if job.isFullyVerified {
            return "checkmark.shield.fill"
        } else if job.mismatchCount > 0 || job.missingCount > 0 {
            return "exclamationmark.shield.fill"
        } else {
            return "xmark.shield.fill"
        }
    }

    private var statusColor: Color {
        if job.isFullyVerified {
            return .green
        } else if job.mismatchCount > 0 || job.missingCount > 0 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatDuration(_ start: Date, _ end: Date) -> String {
        let seconds = end.timeIntervalSince(start)
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(seconds))s"
        }
    }
}

// MARK: - Empty Verification History

struct EmptyVerificationHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No verification history yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Run a verification from the Verification tab to see results here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No sync history yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Completed backup jobs will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - History Job Row

struct HistoryJobRow: View {
    @Environment(AppState.self) private var appState
    let job: SyncJob
    @State private var isExpanded = false
    @State private var showingDeleteAlert = false
    @State private var showingLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Status Icon
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .frame(width: 30)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    if let dest = appState.destinations.first(where: { $0.id == job.destinationID }) {
                        Text(dest.name)
                            .font(.headline)
                    }

                    Text(job.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Stats
                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(job.photosSynced)", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    if job.photosFailed > 0 {
                        Label("\(job.photosFailed)", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button(action: { showingLogs = true }) {
                            Label("View Logs", systemImage: "doc.text")
                        }
                        Divider()
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }

            // Expanded Details
            if isExpanded {
                Divider()

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    DetailItem(label: "Started", value: job.startTime.formatted(date: .omitted, time: .shortened))
                    if let endTime = job.endTime {
                        DetailItem(label: "Ended", value: endTime.formatted(date: .omitted, time: .shortened))
                        DetailItem(label: "Duration", value: formatDuration(job.startTime, endTime))
                    }
                    DetailItem(label: "Scanned", value: "\(job.photosScanned) photos")
                    DetailItem(label: "Synced", value: "\(job.photosSynced) photos")
                    if job.photosFailed > 0 {
                        DetailItem(label: "Failed", value: "\(job.photosFailed) photos")
                    }
                    DetailItem(label: "Data", value: ByteCountFormatter.string(fromByteCount: job.bytesTransferred, countStyle: .file))
                    if let speed = job.averageSpeed {
                        DetailItem(label: "Avg Speed", value: String(format: "%.1f MB/s", speed))
                    }
                    DetailItem(label: "Status", value: job.status.rawValue.capitalized)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
        .alert("Delete Job", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteSyncJob(id: job.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this sync job from history?")
        }
        .sheet(isPresented: $showingLogs) {
            JobLogsView(job: job)
        }
    }

    private var statusIcon: String {
        switch job.status {
        case .completed: return job.photosFailed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .paused: return "pause.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return job.photosFailed > 0 ? .orange : .green
        case .failed: return .red
        case .running: return .blue
        case .paused: return .orange
        case .cancelled: return .gray
        }
    }

    private func formatDuration(_ start: Date, _ end: Date) -> String {
        let seconds = end.timeIntervalSince(start)
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct DetailItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    HistoryView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
