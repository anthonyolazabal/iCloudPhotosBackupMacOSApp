import SwiftUI

struct VerificationJobLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let job: VerificationJob

    @State private var logs: [VerificationLogEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedLevel: VerificationLogEntry.LogLevel?
    @State private var selectedCategory: VerificationLogEntry.VerificationLogCategory?
    @State private var showDebugLogs = false

    var filteredLogs: [VerificationLogEntry] {
        logs.filter { log in
            // Filter by level
            if let level = selectedLevel, log.level != level {
                return false
            }

            // Hide debug logs unless enabled
            if !showDebugLogs && log.level == .debug {
                return false
            }

            // Filter by category
            if let category = selectedCategory, log.category != category {
                return false
            }

            // Filter by search text
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return log.message.lowercased().contains(searchLower) ||
                       (log.photoPath?.lowercased().contains(searchLower) ?? false) ||
                       (log.details?.lowercased().contains(searchLower) ?? false)
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Summary bar
            summaryBar

            Divider()

            // Filters
            filterBar

            Divider()

            // Logs list
            if isLoading {
                ProgressView("Loading logs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logs.isEmpty {
                emptyLogsView
            } else if filteredLogs.isEmpty {
                noMatchingLogsView
            } else {
                logsList
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await loadLogs()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            VStack(alignment: .leading, spacing: 2) {
                Text("Verification Logs")
                    .font(.headline)

                if let dest = appState.destinations.first(where: { $0.id == job.destinationID }) {
                    Text("\(dest.name) - \(job.startTime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Export button
            Button(action: exportLogs) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            // Refresh button
            Button(action: {
                Task { await loadLogs() }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            ForEach(VerificationLogEntry.LogLevel.allCases, id: \.self) { level in
                if level != .debug || showDebugLogs {
                    let count = logs.filter { $0.level == level }.count
                    if count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: level.icon)
                                .foregroundStyle(colorForLevel(level))
                            Text("\(count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(level.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorForLevel(level).opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Text("\(logs.count) total entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 300)

            // Level filter
            Picker("Level", selection: $selectedLevel) {
                Text("All Levels").tag(nil as VerificationLogEntry.LogLevel?)
                Divider()
                ForEach(VerificationLogEntry.LogLevel.allCases.filter { $0 != .debug || showDebugLogs }, id: \.self) { level in
                    Label(level.rawValue, systemImage: level.icon).tag(level as VerificationLogEntry.LogLevel?)
                }
            }
            .frame(width: 140)

            // Category filter
            Picker("Category", selection: $selectedCategory) {
                Text("All Categories").tag(nil as VerificationLogEntry.VerificationLogCategory?)
                Divider()
                ForEach(VerificationLogEntry.VerificationLogCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon).tag(category as VerificationLogEntry.VerificationLogCategory?)
                }
            }
            .frame(width: 160)

            Spacer()

            // Show debug toggle
            Toggle("Debug", isOn: $showDebugLogs)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Logs List

    private var logsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredLogs) { log in
                    VerificationLogEntryRow(log: log)
                    Divider()
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyLogsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No logs available")
                .font(.title3)
                .fontWeight(.medium)

            Text("This verification job doesn't have any log entries")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchingLogsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No matching logs")
                .font(.title3)
                .fontWeight(.medium)

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Clear Filters") {
                searchText = ""
                selectedLevel = nil
                selectedCategory = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadLogs() async {
        isLoading = true

        do {
            logs = try appState.database.getVerificationLogs(jobID: job.id)
        } catch {
            logs = []
        }

        isLoading = false
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "verification_logs_\(job.startTime.ISO8601Format()).txt"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                exportLogsToFile(url)
            }
        }
    }

    private func exportLogsToFile(_ url: URL) {
        var content = "Verification Job Logs\n"
        content += "====================\n\n"
        content += "Job ID: \(job.id)\n"
        content += "Type: \(job.type.rawValue)\n"
        content += "Started: \(job.startTime.formatted())\n"
        if let endTime = job.endTime {
            content += "Ended: \(endTime.formatted())\n"
        }
        content += "Total Photos: \(job.totalPhotos)\n"
        content += "Verified: \(job.verifiedCount)\n"
        content += "Mismatches: \(job.mismatchCount)\n"
        content += "Missing: \(job.missingCount)\n"
        content += "Errors: \(job.errorCount)\n"
        content += "\n---\n\n"

        for log in logs {
            let timestamp = log.timestamp.formatted(date: .omitted, time: .standard)
            content += "[\(timestamp)] [\(log.level.rawValue)] [\(log.category.rawValue)] \(log.message)\n"

            if let photoPath = log.photoPath {
                content += "  Photo: \(photoPath)\n"
            }

            if let details = log.details {
                content += "  Details: \(details)\n"
            }
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Handle error
        }
    }

    private func colorForLevel(_ level: VerificationLogEntry.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

// MARK: - Verification Log Entry Row

struct VerificationLogEntryRow: View {
    let log: VerificationLogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Level icon
                Image(systemName: log.level.icon)
                    .foregroundStyle(colorForLevel)
                    .frame(width: 20)

                // Timestamp
                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                // Category badge
                Text(log.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                // Message
                Text(log.message)
                    .font(.subheadline)
                    .lineLimit(isExpanded ? nil : 2)

                Spacer()

                // Expand button if there are details
                if log.details != nil || log.photoPath != nil {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let photoPath = log.photoPath {
                        HStack(spacing: 4) {
                            Text("Photo Path:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(photoPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    if let details = log.details {
                        Text("Details:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(4)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(backgroundForLevel)
    }

    private var colorForLevel: Color {
        switch log.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private var backgroundForLevel: Color {
        switch log.level {
        case .error: return .red.opacity(0.05)
        case .warning: return .orange.opacity(0.05)
        case .success: return .green.opacity(0.03)
        default: return .clear
        }
    }
}

#Preview {
    VerificationJobLogsView(job: VerificationJob(
        destinationID: UUID(),
        type: .quick,
        totalPhotos: 10,
        verifiedCount: 8,
        mismatchCount: 1,
        missingCount: 1,
        errorCount: 0
    ))
    .environment(AppState())
    .frame(width: 900, height: 700)
}
