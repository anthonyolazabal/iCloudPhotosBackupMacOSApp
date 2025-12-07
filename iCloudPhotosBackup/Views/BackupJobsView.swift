import SwiftUI

struct BackupJobsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewJob = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup Jobs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Start and manage backup operations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { showingNewJob = true }) {
                    Label("New Backup", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.destinations.isEmpty)
            }
            .padding()

            Divider()

            // Active Sync
            if let progress = appState.currentSyncProgress {
                ActiveSyncView(progress: progress)
                Divider()
            }

            // Quick Actions
            if !appState.destinations.isEmpty && appState.currentSyncProgress == nil {
                QuickBackupActions()
                Divider()
            }

            // Info / Empty State
            if appState.destinations.isEmpty {
                EmptyJobsView()
            } else {
                JobsInfoView()
            }
        }
        .sheet(isPresented: $showingNewJob) {
            NewBackupJobSheet()
        }
    }
}

// MARK: - Active Sync View

struct ActiveSyncView: View {
    @Environment(AppState.self) private var appState
    let progress: SyncProgress
    @State private var currentJob: SyncJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Sync")
                .font(.headline)

            // Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(progress.photosCompleted) of \(progress.totalPhotos) photos")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(progress.progress * 100))%")
                        .font(.subheadline)
                        .monospacedDigit()
                }

                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
            }

            // Details Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatItem(label: "Speed", value: String(format: "%.1f MB/s", progress.currentSpeed))
                StatItem(label: "Failed", value: "\(progress.photosFailed)")
                if let eta = progress.estimatedTimeRemaining {
                    StatItem(label: "ETA", value: formatDuration(eta))
                }
            }

            if let currentPhoto = progress.currentPhotoName {
                Text("Currently: \(currentPhoto)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Controls
            HStack(spacing: 12) {
                if appState.syncEngine.state == .syncing {
                    Button(action: { Task { try? await appState.pauseSync() } }) {
                        Label("Pause", systemImage: "pause.fill")
                    }
                } else if appState.syncEngine.state == .paused {
                    Button(action: { Task { try? await appState.resumeSync() } }) {
                        Label("Resume", systemImage: "play.fill")
                    }
                }

                Button(role: .destructive, action: { Task { try? await appState.cancelSync() } }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }

                Spacer()

                // View Logs button
                Button(action: {
                    // Flush logs before showing to ensure latest logs are visible
                    appState.syncEngine.flushLogs()
                    if let jobID = appState.syncEngine.currentJobID,
                       let job = try? appState.database.getSyncJob(id: jobID) {
                        currentJob = job
                    }
                }) {
                    Label("View Logs", systemImage: "doc.text")
                }
                .disabled(appState.syncEngine.currentJobID == nil)

                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .sheet(item: $currentJob) { job in
            JobLogsView(job: job)
        }
    }

    private var stateText: String {
        switch appState.syncEngine.state {
        case .idle: return "Idle"
        case .preparing: return "Preparing..."
        case .syncing: return "Syncing"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct StatItem: View {
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
                .monospacedDigit()
        }
    }
}

// MARK: - Quick Backup Actions

struct QuickBackupActions: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Backup")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DateRangeFilter.quickOptions, id: \.title) { option in
                        QuickBackupCard(option: option)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

struct QuickBackupCard: View {
    @Environment(AppState.self) private var appState
    let option: (title: String, filter: DateRangeFilter)

    var body: some View {
        Button(action: {
            startBackup()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("All destinations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 100, alignment: .topLeading)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startBackup() {
        guard let firstDestination = appState.destinations.first else {
            appState.errorMessage = "No destination available for backup"
            return
        }

        Task {
            do {
                try await appState.startSync(
                    destinationID: firstDestination.id,
                    filter: option.filter
                )
            } catch {
                appState.errorMessage = "Backup failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Empty State

struct EmptyJobsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Destinations Available")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Add a destination first before starting a backup")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Jobs Info

struct JobsInfoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("How Backups Work")
                    .font(.headline)

                Text("Backups will only upload new or modified photos. Already backed up photos are automatically skipped for efficiency.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 24) {
                InfoBadge(icon: "checkmark.circle.fill", text: "Deduplication", color: .green)
                InfoBadge(icon: "arrow.triangle.2.circlepath", text: "Auto-Retry", color: .blue)
                InfoBadge(icon: "lock.fill", text: "Checksums", color: .orange)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InfoBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(width: 100)
    }
}

// MARK: - New Backup Job Sheet

struct NewBackupJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedDestination: UUID?
    @State private var selectedFilter: ScheduledBackupJob.DateRangeFilterType = .fullLibrary
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()

    // Schedule options
    @State private var jobName: String = ""
    @State private var isScheduled: Bool = false
    @State private var scheduleMode: ScheduleMode = .oneTime
    @State private var scheduledDate = Date()
    @State private var dailyHour: Int = 2
    @State private var dailyMinute: Int = 0
    @State private var weeklyDay: Int = 1  // Sunday
    @State private var weeklyHour: Int = 2
    @State private var weeklyMinute: Int = 0

    enum ScheduleMode: String, CaseIterable {
        case oneTime = "One Time"
        case daily = "Daily"
        case weekly = "Weekly"

        var icon: String {
            switch self {
            case .oneTime: return "calendar"
            case .daily: return "clock"
            case .weekly: return "calendar.badge.clock"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Destination", selection: $selectedDestination) {
                        Text("Select...").tag(nil as UUID?)
                        ForEach(appState.destinations) { dest in
                            Text(dest.name).tag(dest.id as UUID?)
                        }
                    }
                }

                Section("Photos to Backup") {
                    Picker("Time Range", selection: $selectedFilter) {
                        ForEach(ScheduledBackupJob.DateRangeFilterType.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                }

                Section("Schedule") {
                    Toggle("Schedule this backup", isOn: $isScheduled)

                    if isScheduled {
                        TextField("Job Name", text: $jobName)
                            .textFieldStyle(.roundedBorder)

                        Picker("Frequency", selection: $scheduleMode) {
                            ForEach(ScheduleMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch scheduleMode {
                        case .oneTime:
                            DatePicker("Run at", selection: $scheduledDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

                        case .daily:
                            HStack {
                                Text("Run daily at")
                                Picker("Hour", selection: $dailyHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .frame(width: 60)
                                Text(":")
                                Picker("Minute", selection: $dailyMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .frame(width: 60)
                            }

                        case .weekly:
                            Picker("Day of Week", selection: $weeklyDay) {
                                ForEach(1...7, id: \.self) { day in
                                    Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                                }
                            }
                            HStack {
                                Text("At")
                                Picker("Hour", selection: $weeklyHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .frame(width: 60)
                                Text(":")
                                Picker("Minute", selection: $weeklyMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .frame(width: 60)
                            }
                        }
                    }
                }

                Section {
                    if isScheduled {
                        Text("The backup will run automatically at the scheduled time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Only new or modified photos will be uploaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isScheduled ? "Schedule Backup" : "New Backup Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isScheduled ? "Schedule" : "Start Backup") {
                        if isScheduled {
                            scheduleBackup()
                        } else {
                            startBackup()
                        }
                    }
                    .disabled(selectedDestination == nil || (isScheduled && jobName.isEmpty))
                }
            }
        }
        .frame(width: 500, height: isScheduled ? 500 : 350)
        .onAppear {
            // Set default job name based on destination
            if let destID = selectedDestination,
               let dest = appState.destinations.first(where: { $0.id == destID }) {
                jobName = "\(dest.name) Backup"
            }
        }
        .onChange(of: selectedDestination) { _, newValue in
            if let destID = newValue,
               let dest = appState.destinations.first(where: { $0.id == destID }) {
                if jobName.isEmpty {
                    jobName = "\(dest.name) Backup"
                }
            }
        }
    }

    private func startBackup() {
        guard let destID = selectedDestination else { return }

        // Dismiss immediately so user can see progress
        dismiss()

        // Start sync in background (don't await - let it run)
        Task {
            try? await appState.startSync(destinationID: destID, filter: selectedFilter.toDateRangeFilter)
        }
    }

    private func scheduleBackup() {
        guard let destID = selectedDestination else { return }

        let scheduleType: ScheduledBackupJob.ScheduleType
        switch scheduleMode {
        case .oneTime:
            scheduleType = .oneTime(scheduledDate: scheduledDate)
        case .daily:
            scheduleType = .daily(hour: dailyHour, minute: dailyMinute)
        case .weekly:
            scheduleType = .weekly(dayOfWeek: weeklyDay, hour: weeklyHour, minute: weeklyMinute)
        }

        var job = ScheduledBackupJob(
            destinationID: destID,
            name: jobName,
            scheduleType: scheduleType,
            filter: selectedFilter
        )

        // Calculate initial next run time
        job.nextRunTime = job.calculateNextRunTime()

        Task {
            await appState.addScheduledBackupJob(job)
            dismiss()
        }
    }
}

// MARK: - Date Range Filter Extension

extension DateRangeFilter {
    static var quickOptions: [(title: String, filter: DateRangeFilter)] {
        [
            ("Last 24 Hours", .last24Hours),
            ("Last 7 Days", .last7Days),
            ("Last 30 Days", .last30Days),
            ("Last 90 Days", .last90Days),
            ("Full Library", .fullLibrary)
        ]
    }
}

#Preview {
    BackupJobsView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
