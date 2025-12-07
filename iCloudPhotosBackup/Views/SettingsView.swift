import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure app preferences")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            Form {
                GeneralSection()
                NotificationsSection()
                ScheduleSection()
                SyncSection()
                ExportSection()
                EncryptionSection()
                AdvancedSection()
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - General Section

struct GeneralSection: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showingLaunchError = false
    @State private var launchError: String?

    var body: some View {
        Section("General") {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try LaunchAtLogin.enable()
                        } else {
                            try LaunchAtLogin.disable()
                        }
                    } catch {
                        launchError = error.localizedDescription
                        showingLaunchError = true
                        launchAtLogin = !newValue // Revert
                    }
                }

            LabeledContent("Version", value: "1.0.0")

            LabeledContent("Database Location") {
                Text("~/Library/Application Support/iCloudPhotosBackup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Launch at Login Error", isPresented: $showingLaunchError) {
            Button("OK") { }
        } message: {
            if let error = launchError {
                Text(error)
            }
        }
    }
}

// MARK: - Notifications Section

struct NotificationsSection: View {
    @State private var notificationsEnabled = NotificationService.shared.notificationsEnabled
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingSystemSettings = false

    var body: some View {
        Section("Notifications") {
            Toggle("Enable Notifications", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, newValue in
                    NotificationService.shared.notificationsEnabled = newValue
                }

            if authorizationStatus == .denied {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Notifications are disabled in System Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Text("Receive notifications for backup and verification job status updates")
                .font(.caption)
                .foregroundStyle(.secondary)

            if notificationsEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You will be notified when:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Group {
                        Label("Backup jobs start, complete, or fail", systemImage: "arrow.clockwise.circle")
                        Label("Verification jobs complete", systemImage: "checkmark.shield")
                        Label("Scheduled backups run", systemImage: "calendar.badge.clock")
                        Label("Issues are detected in backups", systemImage: "exclamationmark.triangle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .task {
            authorizationStatus = await NotificationService.shared.checkAuthorizationStatus()
        }
    }
}

// MARK: - Schedule Section

struct ScheduleSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Background Sync Schedule") {
            if let scheduler = appState.backgroundScheduler {
                Toggle("Enable Automatic Backups", isOn: Binding(
                    get: { scheduler.isEnabled },
                    set: { enabled in
                        if enabled {
                            scheduler.enable()
                        } else {
                            scheduler.disable()
                        }
                    }
                ))

                if scheduler.isEnabled {
                    Picker("Frequency", selection: Binding(
                        get: { scheduler.interval },
                        set: { scheduler.updateInterval($0) }
                    )) {
                        ForEach(BackgroundScheduler.presets, id: \.interval) { preset in
                            Text(preset.name).tag(preset.interval)
                        }
                    }

                    Toggle("Require AC Power", isOn: Binding(
                        get: { scheduler.requiresCharging },
                        set: { scheduler.updateRequiresCharging($0) }
                    ))

                    HStack {
                        Text("Preferred Time Window")
                        Spacer()
                        Picker("Start", selection: Binding(
                            get: { scheduler.preferredTimeWindow.start },
                            set: { start in
                                scheduler.updatePreferredTimeWindow(
                                    start: start,
                                    end: scheduler.preferredTimeWindow.end
                                )
                            }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        Text("to")

                        Picker("End", selection: Binding(
                            get: { scheduler.preferredTimeWindow.end },
                            set: { end in
                                scheduler.updatePreferredTimeWindow(
                                    start: scheduler.preferredTimeWindow.start,
                                    end: end
                                )
                            }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    Text("Backups will run automatically within the preferred time window")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Test Schedule Now") {
                        Task {
                            await scheduler.triggerManualSync()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sync Section

struct SyncSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Sync Settings") {
            Stepper("Concurrent Uploads: \(appState.concurrentUploads)", value: Binding(
                get: { appState.concurrentUploads },
                set: { appState.concurrentUploads = $0 }
            ), in: 1...10)

            Text("Higher values use more bandwidth and system resources")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Export Section

struct ExportSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Photo Export") {
            Toggle("Convert HEIC to JPEG", isOn: Binding(
                get: { appState.exportSettings.convertHEICToJPEG },
                set: { appState.exportSettings.convertHEICToJPEG = $0 }
            ))

            if appState.exportSettings.convertHEICToJPEG {
                Slider(
                    value: Binding(
                        get: { appState.exportSettings.jpegQuality },
                        set: { appState.exportSettings.jpegQuality = $0 }
                    ),
                    in: 0.5...1.0
                ) {
                    Text("JPEG Quality: \(Int(appState.exportSettings.jpegQuality * 100))%")
                }
            }

            Picker("Live Photos", selection: Binding(
                get: { appState.exportSettings.livePhotosMode },
                set: { appState.exportSettings.livePhotosMode = $0 }
            )) {
                ForEach(ExportSettings.LivePhotosMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Obfuscate Filenames", isOn: Binding(
                get: { appState.exportSettings.obfuscateFilenames },
                set: { appState.exportSettings.obfuscateFilenames = $0 }
            ))

            Text("Uses random UUIDs instead of original filenames for privacy")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Encryption Section

struct EncryptionSection: View {
    @Environment(AppState.self) private var appState
    @State private var isEncryptionEnabled = false
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var showingSetupSheet = false
    @State private var showingRemoveAlert = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Client-Side Encryption") {
            Toggle("Encrypt Files Before Upload", isOn: Binding(
                get: { appState.exportSettings.encryptFiles },
                set: { newValue in
                    if newValue {
                        // Check if encryption is already configured
                        if appState.encryptionService.hasEncryptionKey() {
                            appState.exportSettings.encryptFiles = true
                        } else {
                            // Show setup sheet
                            showingSetupSheet = true
                        }
                    } else {
                        appState.exportSettings.encryptFiles = false
                    }
                }
            ))

            if appState.exportSettings.encryptFiles {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                    Text("Encryption Active")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button("Change Passphrase") {
                    showingSetupSheet = true
                }

                Button("Remove Encryption", role: .destructive) {
                    showingRemoveAlert = true
                }
            }

            Text("Files are encrypted using AES-256 before upload. You must remember your passphrase to decrypt files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingSetupSheet) {
            EncryptionSetupSheet(
                passphrase: $passphrase,
                confirmPassphrase: $confirmPassphrase,
                errorMessage: $errorMessage,
                onSave: {
                    do {
                        // Validate passphrases match
                        guard passphrase == confirmPassphrase else {
                            errorMessage = "Passphrases do not match"
                            return
                        }

                        // Set up encryption
                        try appState.encryptionService.setupEncryption(passphrase: passphrase)

                        // Enable encryption in settings
                        appState.exportSettings.encryptFiles = true

                        // Clear passphrases
                        passphrase = ""
                        confirmPassphrase = ""
                        errorMessage = nil

                        // Close sheet
                        showingSetupSheet = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                },
                onCancel: {
                    passphrase = ""
                    confirmPassphrase = ""
                    errorMessage = nil
                    showingSetupSheet = false
                }
            )
        }
        .alert("Remove Encryption?", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                do {
                    try appState.encryptionService.removeEncryption()
                    appState.exportSettings.encryptFiles = false
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This will remove your encryption key. Previously encrypted files will remain encrypted and cannot be decrypted without the passphrase.")
        }
        .onAppear {
            isEncryptionEnabled = appState.encryptionService.hasEncryptionKey()
        }
    }
}

// MARK: - Encryption Setup Sheet

struct EncryptionSetupSheet: View {
    @Binding var passphrase: String
    @Binding var confirmPassphrase: String
    @Binding var errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Set Up Encryption")
                .font(.title2)
                .fontWeight(.bold)

            Text("Create a strong passphrase to encrypt your photos. This passphrase is NOT stored and cannot be recovered if lost.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SecureField("Passphrase (min 12 characters)", text: $passphrase)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm Passphrase", text: $confirmPassphrase)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Set Up Encryption") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.count < 12 || confirmPassphrase.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 450)
    }
}

// MARK: - Advanced Section

struct AdvancedSection: View {
    @State private var showingResetAlert = false

    var body: some View {
        Section("Advanced") {
            Button("View Logs") {
                // Open Console.app filtered to app
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Reset All Settings", role: .destructive) {
                showingResetAlert = true
            }
        }
        .alert("Reset All Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("This will reset all preferences to defaults. Destinations and sync history will not be affected.")
        }
    }

    private func resetSettings() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}

// MARK: - About Section

struct AboutSection: View {
    var body: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 8) {
                Text("iCloud Photos Backup")
                    .font(.headline)

                Text("A macOS application for backing up iCloud Photos to cloud storage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label("Read-only access", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Label("Encrypted uploads", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    Label("Deduplication", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
