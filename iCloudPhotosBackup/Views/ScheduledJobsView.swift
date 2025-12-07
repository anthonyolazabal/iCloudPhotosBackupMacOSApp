import SwiftUI

struct ScheduledJobsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewJob = false
    @State private var selectedJob: ScheduledBackupJob?
    @State private var showingDeleteAlert = false
    @State private var jobToDelete: ScheduledBackupJob?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled Jobs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Manage automatic backup schedules")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { showingNewJob = true }) {
                    Label("New Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.destinations.isEmpty)
            }
            .padding()

            Divider()

            // Content
            if appState.scheduledJobs.isEmpty {
                EmptyScheduledJobsView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.scheduledJobs) { job in
                            ScheduledJobRow(
                                job: job,
                                destination: appState.destinations.first(where: { $0.id == job.destinationID }),
                                onToggle: { toggleJob(job) },
                                onEdit: { selectedJob = job },
                                onDelete: {
                                    jobToDelete = job
                                    showingDeleteAlert = true
                                },
                                onRunNow: { runJobNow(job) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingNewJob) {
            NewBackupJobSheet()
        }
        .sheet(item: $selectedJob) { job in
            EditScheduledJobSheet(job: job)
        }
        .alert("Delete Scheduled Job", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                jobToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let job = jobToDelete {
                    deleteJob(job)
                }
            }
        } message: {
            Text("Are you sure you want to delete this scheduled job? This action cannot be undone.")
        }
        .task {
            await appState.loadScheduledJobs()
        }
    }

    private func toggleJob(_ job: ScheduledBackupJob) {
        Task {
            await appState.toggleScheduledJob(id: job.id, isEnabled: !job.isEnabled)
        }
    }

    private func deleteJob(_ job: ScheduledBackupJob) {
        Task {
            await appState.deleteScheduledJob(id: job.id)
            jobToDelete = nil
        }
    }

    private func runJobNow(_ job: ScheduledBackupJob) {
        Task {
            await appState.runScheduledJobNow(job)
        }
    }
}

// MARK: - Scheduled Job Row

struct ScheduledJobRow: View {
    let job: ScheduledBackupJob
    let destination: DestinationRecord?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRunNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Status indicator
                Circle()
                    .fill(job.isEnabled ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Label(destination?.name ?? "Unknown", systemImage: "externaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Label(job.filter.rawValue, systemImage: "photo.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Schedule badge
                Text(job.scheduleType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(scheduleColor.opacity(0.2))
                    .foregroundStyle(scheduleColor)
                    .cornerRadius(4)
            }

            // Schedule details
            HStack {
                Image(systemName: scheduleIcon)
                    .foregroundStyle(.secondary)
                Text(job.scheduleType.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Next run / Last run info
            HStack(spacing: 20) {
                if let nextRun = job.nextRunTime {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Run")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(nextRun.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastRun = job.lastRunTime {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Run")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 4) {
                            Text(lastRun.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            if let status = job.lastRunStatus {
                                Image(systemName: statusIcon(for: status))
                                    .foregroundStyle(statusColor(for: status))
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onRunNow) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Run Now")
                    .disabled(!job.isEnabled)

                    Toggle("", isOn: .constant(job.isEnabled))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: job.isEnabled) { _, _ in
                            onToggle()
                        }

                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var scheduleIcon: String {
        switch job.scheduleType {
        case .oneTime: return "calendar"
        case .daily: return "clock"
        case .weekly: return "calendar.badge.clock"
        case .custom: return "timer"
        }
    }

    private var scheduleColor: Color {
        switch job.scheduleType {
        case .oneTime: return .orange
        case .daily: return .blue
        case .weekly: return .purple
        case .custom: return .teal
        }
    }

    private func statusIcon(for status: SyncJob.SyncJobStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        case .running, .paused: return "clock.fill"
        }
    }

    private func statusColor(for status: SyncJob.SyncJobStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .running, .paused: return .blue
        }
    }
}

// MARK: - Empty State

struct EmptyScheduledJobsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Scheduled Jobs")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Create a scheduled backup to automatically sync your photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: 24) {
                ScheduleInfoBadge(icon: "clock", text: "Daily", color: .blue)
                ScheduleInfoBadge(icon: "calendar", text: "Weekly", color: .purple)
                ScheduleInfoBadge(icon: "calendar.badge.plus", text: "One-time", color: .orange)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScheduleInfoBadge: View {
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
        .frame(width: 80)
    }
}

// MARK: - Edit Scheduled Job Sheet

struct EditScheduledJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let job: ScheduledBackupJob

    @State private var jobName: String = ""
    @State private var selectedFilter: ScheduledBackupJob.DateRangeFilterType = .fullLibrary
    @State private var scheduleMode: ScheduleMode = .oneTime
    @State private var scheduledDate = Date()
    @State private var dailyHour: Int = 2
    @State private var dailyMinute: Int = 0
    @State private var weeklyDay: Int = 1
    @State private var weeklyHour: Int = 2
    @State private var weeklyMinute: Int = 0

    enum ScheduleMode: String, CaseIterable {
        case oneTime = "One Time"
        case daily = "Daily"
        case weekly = "Weekly"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    TextField("Job Name", text: $jobName)
                        .textFieldStyle(.roundedBorder)

                    if let dest = appState.destinations.first(where: { $0.id == job.destinationID }) {
                        LabeledContent("Destination", value: dest.name)
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
                    Picker("Frequency", selection: $scheduleMode) {
                        ForEach(ScheduleMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
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
            .formStyle(.grouped)
            .navigationTitle("Edit Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(jobName.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadJobData()
        }
    }

    private func loadJobData() {
        jobName = job.name
        selectedFilter = job.filter

        switch job.scheduleType {
        case .oneTime(let date):
            scheduleMode = .oneTime
            scheduledDate = date
        case .daily(let hour, let minute):
            scheduleMode = .daily
            dailyHour = hour
            dailyMinute = minute
        case .weekly(let day, let hour, let minute):
            scheduleMode = .weekly
            weeklyDay = day
            weeklyHour = hour
            weeklyMinute = minute
        case .custom:
            scheduleMode = .daily
        }
    }

    private func saveChanges() {
        let scheduleType: ScheduledBackupJob.ScheduleType
        switch scheduleMode {
        case .oneTime:
            scheduleType = .oneTime(scheduledDate: scheduledDate)
        case .daily:
            scheduleType = .daily(hour: dailyHour, minute: dailyMinute)
        case .weekly:
            scheduleType = .weekly(dayOfWeek: weeklyDay, hour: weeklyHour, minute: weeklyMinute)
        }

        var updatedJob = job
        updatedJob.name = jobName
        updatedJob.filter = selectedFilter
        updatedJob.scheduleType = scheduleType
        updatedJob.nextRunTime = updatedJob.calculateNextRunTime()

        Task {
            await appState.updateScheduledJob(updatedJob)
            dismiss()
        }
    }
}

#Preview {
    ScheduledJobsView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
