import SwiftUI

struct VerificationView: View {
    @Environment(AppState.self) private var appState
    @State private var showingVerificationSheet = false
    @State private var lastVerificationResult: VerificationJobResult?
    @State private var lastGapResult: GapDetectionResult?
    @State private var isRunningVerification = false
    @State private var isRunningGapDetection = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verification")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Verify backup integrity and find gaps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { showingVerificationSheet = true }) {
                    Label("New Verification", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.destinations.isEmpty)
            }
            .padding()

            Divider()

            // Active Verification Progress
            if let progress = appState.verificationProgress, progress.isRunning {
                ActiveVerificationView(progress: progress)
                Divider()
            }

            ScrollView {
                VStack(spacing: 24) {
                    // Quick Actions
                    if !appState.destinations.isEmpty && !isRunningVerification {
                        QuickVerificationSection()
                    }

                    // Last Verification Result
                    if let result = lastVerificationResult {
                        VerificationResultCard(result: result)
                    }

                    // Gap Detection Result
                    if let gapResult = lastGapResult {
                        GapDetectionResultCard(result: gapResult)
                    }

                    // Empty State
                    if appState.destinations.isEmpty {
                        EmptyVerificationView()
                    } else if lastVerificationResult == nil && lastGapResult == nil {
                        VerificationInfoView()
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingVerificationSheet) {
            NewVerificationSheet(
                onComplete: { result in
                    lastVerificationResult = result
                },
                onGapDetection: { result in
                    lastGapResult = result
                }
            )
        }
        .alert("Verification Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - Active Verification View

struct ActiveVerificationView: View {
    @Environment(AppState.self) private var appState
    let progress: VerificationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verification in Progress")
                .font(.headline)

            // Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(progress.photosChecked) of \(progress.totalPhotos) photos verified")
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

            // Stats Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                VerificationStatItem(
                    label: "Verified",
                    value: "\(progress.verifiedCount)",
                    color: .green
                )
                VerificationStatItem(
                    label: "Mismatches",
                    value: "\(progress.mismatchCount)",
                    color: progress.mismatchCount > 0 ? .orange : .secondary
                )
                VerificationStatItem(
                    label: "Missing",
                    value: "\(progress.missingCount)",
                    color: progress.missingCount > 0 ? .red : .secondary
                )
                VerificationStatItem(
                    label: "Errors",
                    value: "\(progress.errorCount)",
                    color: progress.errorCount > 0 ? .red : .secondary
                )
            }

            if let currentPath = progress.currentPhotoPath {
                Text("Checking: \(currentPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Cancel Button
            HStack {
                Button(role: .destructive, action: {
                    appState.verificationService?.cancel()
                }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}

struct VerificationStatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Quick Verification Section

struct QuickVerificationSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickVerificationCard(
                    title: "Quick Check",
                    description: "Verify 10 random photos",
                    icon: "bolt.shield",
                    action: {
                        Task {
                            await runQuickVerification()
                        }
                    }
                )

                QuickVerificationCard(
                    title: "Gap Detection",
                    description: "Find unsynced photos",
                    icon: "doc.badge.gearshape",
                    action: {
                        Task {
                            await runGapDetection()
                        }
                    }
                )

                QuickVerificationCard(
                    title: "Full Verification",
                    description: "Verify all photos",
                    icon: "checkmark.shield.fill",
                    action: {
                        Task {
                            await runFullVerification()
                        }
                    }
                )
            }
        }
    }

    private func runQuickVerification() async {
        guard let dest = appState.destinations.first else { return }

        do {
            _ = try await appState.runVerification(
                destinationID: dest.id,
                type: .quick,
                sampleSize: 10
            )
        } catch {
            appState.errorMessage = "Quick verification failed: \(error.localizedDescription)"
        }
    }

    private func runGapDetection() async {
        guard let dest = appState.destinations.first else { return }

        do {
            _ = try await appState.runGapDetection(destinationID: dest.id)
        } catch {
            appState.errorMessage = "Gap detection failed: \(error.localizedDescription)"
        }
    }

    private func runFullVerification() async {
        guard let dest = appState.destinations.first else { return }

        do {
            _ = try await appState.runVerification(
                destinationID: dest.id,
                type: .full
            )
        } catch {
            appState.errorMessage = "Full verification failed: \(error.localizedDescription)"
        }
    }
}

struct QuickVerificationCard: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Verification Result Card

struct VerificationResultCard: View {
    let result: VerificationJobResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Last Verification", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Text(formatDate(result.endTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Summary
            HStack(spacing: 24) {
                ResultStat(
                    value: result.verifiedCount,
                    total: result.totalPhotos,
                    label: "Verified",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                if result.mismatchCount > 0 {
                    ResultStat(
                        value: result.mismatchCount,
                        total: result.totalPhotos,
                        label: "Mismatches",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }

                if result.missingCount > 0 {
                    ResultStat(
                        value: result.missingCount,
                        total: result.totalPhotos,
                        label: "Missing",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }

                if result.errorCount > 0 {
                    ResultStat(
                        value: result.errorCount,
                        total: result.totalPhotos,
                        label: "Errors",
                        icon: "exclamationmark.circle.fill",
                        color: .red
                    )
                }
            }

            // Progress indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Integrity Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(result.successRate * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.separatorColor))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(result.isFullyVerified ? Color.green : Color.orange)
                            .frame(width: geo.size.width * result.successRate, height: 8)
                    }
                }
                .frame(height: 8)
            }

            // Duration
            Text("Completed in \(formatDuration(result.endTime.timeIntervalSince(result.startTime)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
        } else {
            return "\(Int(seconds / 3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
}

struct ResultStat: View {
    let value: Int
    let total: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Gap Detection Result Card

struct GapDetectionResultCard: View {
    let result: GapDetectionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Gap Detection", systemImage: "doc.badge.gearshape")
                    .font(.headline)
                Spacer()
                if result.gapCount == 0 {
                    Label("All synced", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("\(result.gapCount) gaps found", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Stats
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                GapStatItem(
                    label: "In Library",
                    value: "\(result.totalInLibrary)",
                    icon: "photo.on.rectangle"
                )
                GapStatItem(
                    label: "Synced",
                    value: "\(result.totalSynced)",
                    icon: "checkmark.circle"
                )
                GapStatItem(
                    label: "Sync Coverage",
                    value: String(format: "%.1f%%", result.syncPercentage),
                    icon: "chart.pie"
                )
            }

            if result.gapCount > 0 {
                Divider()

                HStack(spacing: 24) {
                    if !result.unsyncedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("New Photos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.unsyncedPhotos.count)")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                    }

                    if !result.modifiedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Modified")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.modifiedPhotos.count)")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                    }

                    Spacer()

                    Button("Sync Now") {
                        // Trigger sync for missing photos
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct GapStatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty State

struct EmptyVerificationView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Destinations Available")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Add a destination and sync some photos before running verification")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Info View

struct VerificationInfoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("About Verification")
                    .font(.headline)

                Text("Verification ensures your backups are complete and uncorrupted. Run regular checks to maintain confidence in your backup integrity.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 24) {
                VerificationInfoBadge(icon: "checkmark.shield.fill", text: "Checksum Verify", color: .green)
                VerificationInfoBadge(icon: "doc.badge.gearshape", text: "Gap Detection", color: .blue)
                VerificationInfoBadge(icon: "arrow.counterclockwise", text: "Auto Re-upload", color: .orange)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VerificationInfoBadge: View {
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

// MARK: - New Verification Sheet

struct NewVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedDestination: UUID?
    @State private var verificationType: VerificationJobType = .quick
    @State private var quickSampleSize = 10
    @State private var isRunning = false
    @State private var errorMessage: String?

    var onComplete: (VerificationJobResult) -> Void
    var onGapDetection: (GapDetectionResult) -> Void

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

                Section("Verification Type") {
                    Picker("Type", selection: $verificationType) {
                        Text("Quick Check").tag(VerificationJobType.quick)
                        Text("Full Verification").tag(VerificationJobType.full)
                        Text("Gap Detection Only").tag(VerificationJobType.incremental)
                    }
                    .pickerStyle(.segmented)

                    switch verificationType {
                    case .quick:
                        Stepper("Sample Size: \(quickSampleSize)", value: $quickSampleSize, in: 5...100, step: 5)
                        Text("Randomly verify \(quickSampleSize) photos for a quick integrity check")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .full:
                        Text("Verify checksums of all synced photos. This may take a while for large libraries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .incremental:
                        Text("Find photos in your library that haven't been backed up yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isRunning {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running verification...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Verification")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task { await startVerification() }
                    }
                    .disabled(selectedDestination == nil || isRunning)
                }
            }
            .alert("Verification Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func startVerification() async {
        guard let destID = selectedDestination else { return }

        isRunning = true

        do {
            switch verificationType {
            case .quick:
                let result = try await appState.runVerification(
                    destinationID: destID,
                    type: .quick,
                    sampleSize: quickSampleSize
                )
                onComplete(result)
            case .full:
                let result = try await appState.runVerification(
                    destinationID: destID,
                    type: .full
                )
                onComplete(result)
            case .incremental:
                let result = try await appState.runGapDetection(destinationID: destID)
                onGapDetection(result)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }
}

#Preview {
    VerificationView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
