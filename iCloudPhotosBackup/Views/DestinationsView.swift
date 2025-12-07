import SwiftUI

struct DestinationsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddDestination = false
    @State private var selectedDestination: DestinationRecord?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destinations")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Manage your backup destinations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { showingAddDestination = true }) {
                    Label("Add Destination", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Destinations List
            if appState.destinations.isEmpty {
                EmptyDestinationsView()
            } else {
                List(appState.destinations) { destination in
                    DestinationListRow(destination: destination)
                        .onTapGesture {
                            selectedDestination = destination
                        }
                }
            }
        }
        .sheet(isPresented: $showingAddDestination) {
            AddDestinationSheet()
        }
        .sheet(item: $selectedDestination) { destination in
            DestinationDetailSheet(destination: destination)
        }
    }
}

// MARK: - Empty State

struct EmptyDestinationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No destinations configured")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add a storage destination to start backing up your photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Destination List Row

struct DestinationListRow: View {
    @Environment(AppState.self) private var appState
    let destination: DestinationRecord

    @State private var isTesting = false
    @State private var testError: String?
    @State private var showingPhotoBrowser = false

    private var destinationIcon: String {
        switch destination.type {
        case .s3:
            return "externaldrive.fill"
        case .smb:
            return "externaldrive.fill.badge.wifi"
        default:
            return "externaldrive.fill"
        }
    }

    private var destinationBadge: String {
        switch destination.type {
        case .s3:
            if let config = try? JSONDecoder().decode(S3Configuration.self, from: destination.configJSON) {
                return config.provider.rawValue
            }
            return "S3"
        case .smb:
            if let config = try? JSONDecoder().decode(SMBConfiguration.self, from: destination.configJSON) {
                return config.serverAddress
            }
            return "SMB"
        default:
            return destination.type.rawValue.uppercased()
        }
    }

    private var badgeColor: Color {
        switch destination.type {
        case .s3:
            return .blue
        case .smb:
            return .purple
        default:
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon with status overlay
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: destinationIcon)
                    .font(.largeTitle)
                    .foregroundStyle(badgeColor)
                    .frame(width: 50)

                // Status indicator overlay
                Circle()
                    .fill(healthColor)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color(.windowBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: 4, y: 4)
            }

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(destination.name)
                        .font(.headline)

                    // Provider/Server badge
                    Text(destinationBadge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.1))
                        .foregroundStyle(badgeColor)
                        .cornerRadius(4)
                }

                HStack(spacing: 12) {
                    if let stats = appState.stats[destination.id] {
                        Label("\(stats.totalPhotos) photos", systemImage: "photo")
                            .font(.caption)

                        Label(stats.formattedSize, systemImage: "externaldrive")
                            .font(.caption)

                        if let lastSync = stats.lastSyncDate {
                            Label("Synced \(lastSync, style: .relative) ago", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                    } else {
                        Text("No backups yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)

                // Status and last check info
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Testing...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: statusIcon)
                                .font(.caption2)
                                .foregroundStyle(healthColor)
                            Text(healthText)
                                .font(.caption2)
                                .foregroundStyle(healthColor)
                        }
                    }

                    if let lastCheck = destination.lastHealthCheck, !isTesting {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("Checked \(lastCheck, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let error = testError {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Actions
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: { showingPhotoBrowser = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Browse")
                        }
                        .font(.caption)
                        .frame(width: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { testConnection() }) {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Test")
                        }
                        .font(.caption)
                        .frame(width: 70)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingPhotoBrowser) {
            PhotoBrowserView(destination: destination)
        }
        .task {
            // Auto-test on appear if status is unknown or last check was > 1 hour ago
            if destination.healthStatus == .unknown ||
               (destination.lastHealthCheck.map { Date().timeIntervalSince($0) > 3600 } ?? true) {
                await testConnectionAsync()
            }
        }
    }

    private var healthColor: Color {
        switch destination.healthStatus {
        case .healthy: return .green
        case .degraded: return .orange
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }

    private var healthText: String {
        switch destination.healthStatus {
        case .healthy: return "Connected"
        case .degraded: return "Degraded"
        case .unhealthy: return "Offline"
        case .unknown: return "Not tested"
        }
    }

    private var statusIcon: String {
        switch destination.healthStatus {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unhealthy: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func testConnection() {
        Task {
            await testConnectionAsync()
        }
    }

    private func testConnectionAsync() async {
        isTesting = true
        testError = nil

        do {
            let decoder = JSONDecoder()
            switch destination.type {
            case .s3:
                let config = try decoder.decode(S3Configuration.self, from: destination.configJSON)
                _ = try await appState.testDestination(config)
            case .smb:
                let config = try decoder.decode(SMBConfiguration.self, from: destination.configJSON)
                _ = try await appState.testSMBDestination(config)
            default:
                throw DestinationError.invalidConfiguration(reason: "Unknown destination type")
            }
            try appState.database.updateDestinationHealth(id: destination.id, status: .healthy)
            await appState.loadDestinations()
        } catch {
            let errorMessage = error.localizedDescription
            testError = String(errorMessage.prefix(50))
            try? appState.database.updateDestinationHealth(id: destination.id, status: .unhealthy)
            await appState.loadDestinations()
        }

        isTesting = false
    }
}

// MARK: - Add Destination Sheet

struct AddDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var destinationType: DestinationType = .s3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Destination Type Picker
                Picker("Destination Type", selection: $destinationType) {
                    Label("S3 Compatible Storage", systemImage: "externaldrive.fill")
                        .tag(DestinationType.s3)
                    Label("Network Share (SMB)", systemImage: "externaldrive.fill.badge.wifi")
                        .tag(DestinationType.smb)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Show appropriate form based on selection
                if destinationType == .s3 {
                    AddS3DestinationForm()
                } else {
                    AddSMBDestinationForm()
                }
            }
            .navigationTitle("Add Destination")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 750)
    }
}

// MARK: - Add S3 Destination Form

struct AddS3DestinationForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedProvider: S3Configuration.S3Provider = .aws
    @State private var name = ""
    @State private var endpointURL = ""
    @State private var region = "us-east-1"
    @State private var bucketName = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var pathPrefix = ""
    @State private var storageClass: S3Configuration.StorageClass = .standard
    @State private var encryption: S3Configuration.ServerSideEncryption = .none

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(S3Configuration.S3Provider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: selectedProvider) { _, newValue in
                    updateForProvider(newValue)
                }
            }

            Section("Basic Configuration") {
                TextField("Display Name", text: $name)
                TextField("Endpoint URL", text: $endpointURL)

                if selectedProvider == .ovh {
                    Picker("Region", selection: $region) {
                        ForEach(S3Configuration.OVHRegion.allCases, id: \.self) { ovhRegion in
                            Text(ovhRegion.displayName).tag(ovhRegion.rawValue)
                        }
                    }
                    .onChange(of: region) { _, newValue in
                        endpointURL = "https://s3.\(newValue).io.cloud.ovh.net"
                    }
                } else {
                    TextField("Region", text: $region)
                }

                TextField("Bucket Name", text: $bucketName)
            }

            Section("Credentials") {
                TextField("Access Key ID", text: $accessKeyID)
                SecureField("Secret Access Key", text: $secretAccessKey)
            }

            Section("Advanced") {
                TextField("Path Prefix (optional)", text: $pathPrefix)

                Picker("Storage Class", selection: $storageClass) {
                    ForEach(S3Configuration.StorageClass.allCases, id: \.self) { sc in
                        Text(sc.description).tag(sc)
                    }
                }

                Picker("Server-Side Encryption", selection: $encryption) {
                    ForEach(S3Configuration.ServerSideEncryption.allCases, id: \.self) { enc in
                        Text(enc.description).tag(enc)
                    }
                }
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isValid)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let error):
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button("Add Destination") {
                    saveDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .formStyle(.grouped)
    }

    private var isValid: Bool {
        !name.isEmpty && !endpointURL.isEmpty && !region.isEmpty &&
        !bucketName.isEmpty && !accessKeyID.isEmpty && !secretAccessKey.isEmpty
    }

    private func updateForProvider(_ provider: S3Configuration.S3Provider) {
        region = provider.defaultRegion

        switch provider {
        case .aws:
            endpointURL = "https://s3.\(region).amazonaws.com"
        case .minio:
            endpointURL = "http://localhost:9000"
        case .ovh:
            endpointURL = "https://s3.\(region).io.cloud.ovh.net"
        case .backblaze:
            endpointURL = "https://s3.\(region).backblazeb2.com"
        case .wasabi:
            endpointURL = "https://s3.\(region).wasabisys.com"
        case .custom:
            endpointURL = ""
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let config = buildConfiguration()
                _ = try await appState.testDestination(config)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func saveDestination() {
        Task {
            do {
                let config = buildConfiguration()
                try await appState.addDestination(config)
                dismiss()
            } catch {
                testResult = .failure(error.localizedDescription)
            }
        }
    }

    private func buildConfiguration() -> S3Configuration {
        S3Configuration(
            name: name,
            endpointURL: endpointURL,
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            pathPrefix: pathPrefix,
            usePathStyleAccess: selectedProvider.requiresPathStyle,
            storageClass: storageClass,
            serverSideEncryption: encryption,
            provider: selectedProvider
        )
    }
}

// MARK: - Add SMB Destination Form

struct AddSMBDestinationForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    // Server settings
    @State private var name = ""
    @State private var serverAddress = ""
    @State private var port = "445"
    @State private var shareName = ""
    @State private var pathPrefix = ""

    // Authentication
    @State private var authType: SMBConfiguration.SMBAuthType = .credentials
    @State private var username = ""
    @State private var password = ""
    @State private var domain = ""

    // Share discovery
    @State private var discoveredShares: [String] = []
    @State private var isDiscovering = false
    @State private var discoveryError: String?

    // Testing
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Display Name", text: $name)
                    .textContentType(.name)

                TextField("Server Address", text: $serverAddress, prompt: Text("192.168.1.100 or nas.local"))
                    .textContentType(.URL)

                TextField("Port", text: $port)
                    .frame(width: 100)
            }

            Section("Share") {
                HStack {
                    if discoveredShares.isEmpty {
                        TextField("Share Name", text: $shareName)
                    } else {
                        Picker("Share Name", selection: $shareName) {
                            Text("Select a share...").tag("")
                            ForEach(discoveredShares, id: \.self) { share in
                                Text(share).tag(share)
                            }
                        }
                    }

                    Button(action: discoverShares) {
                        if isDiscovering {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverAddress.isEmpty || isDiscovering)
                    .help("Discover available shares")
                }

                if let error = discoveryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Path Prefix (optional)", text: $pathPrefix, prompt: Text("Subfolder within share"))
            }

            Section("Authentication") {
                Picker("Authentication", selection: $authType) {
                    ForEach(SMBConfiguration.SMBAuthType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)

                if authType == .credentials {
                    TextField("Username", text: $username)
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    TextField("Domain (optional)", text: $domain, prompt: Text("WORKGROUP"))
                }
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isValid)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let error):
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button("Add Destination") {
                    saveDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .formStyle(.grouped)
    }

    private var isValid: Bool {
        !name.isEmpty && !serverAddress.isEmpty && !shareName.isEmpty &&
        (authType == .guest || !username.isEmpty)
    }

    private func discoverShares() {
        isDiscovering = true
        discoveryError = nil

        Task {
            do {
                let shares = try await SMBDestinationService.discoverShares(
                    server: serverAddress,
                    username: authType == .credentials ? username : nil,
                    password: authType == .credentials ? password : nil
                )

                await MainActor.run {
                    discoveredShares = shares
                    if shares.isEmpty {
                        discoveryError = "No shares found on server"
                    }
                }
            } catch {
                await MainActor.run {
                    discoveryError = "Discovery failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                isDiscovering = false
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let config = buildConfiguration()
                _ = try await appState.testSMBDestination(config)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func saveDestination() {
        Task {
            do {
                let config = buildConfiguration()
                try await appState.addSMBDestination(config)
                dismiss()
            } catch {
                testResult = .failure(error.localizedDescription)
            }
        }
    }

    private func buildConfiguration() -> SMBConfiguration {
        SMBConfiguration(
            name: name,
            serverAddress: serverAddress,
            shareName: shareName,
            port: Int(port) ?? 445,
            pathPrefix: pathPrefix,
            authType: authType,
            username: username,
            password: password,
            domain: domain
        )
    }
}

// MARK: - Destination Detail Sheet

struct DestinationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let destination: DestinationRecord

    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var showingPhotoBrowser = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Information") {
                    LabeledContent("Name", value: destination.name)
                    LabeledContent("Type", value: destination.type.rawValue.uppercased())
                    LabeledContent("Created", value: destination.createdAt, format: .dateTime)
                }

                if let stats = appState.stats[destination.id] {
                    Section("Statistics") {
                        LabeledContent("Photos Backed Up", value: "\(stats.totalPhotos)")
                        LabeledContent("Storage Used", value: stats.formattedSize)
                        if let lastSync = stats.lastSyncDate {
                            LabeledContent("Last Sync", value: lastSync, format: .dateTime)
                        }
                    }
                }

                Section("Health") {
                    LabeledContent("Status", value: destination.healthStatus.rawValue.capitalized)
                    if let lastCheck = destination.lastHealthCheck {
                        LabeledContent("Last Check", value: lastCheck, format: .dateTime)
                    }
                }

                Section {
                    Button(action: { showingPhotoBrowser = true }) {
                        Label("Browse Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Configuration", systemImage: "pencil")
                    }

                    Button("Delete Destination", role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(destination.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
        .alert("Delete Destination?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteDestination()
            }
        } message: {
            Text("This will remove the destination configuration. Backed up photos will remain in storage.")
        }
        .sheet(isPresented: $showingEditSheet) {
            EditDestinationSheet(destination: destination)
        }
        .sheet(isPresented: $showingPhotoBrowser) {
            PhotoBrowserView(destination: destination)
        }
    }

    private func deleteDestination() {
        Task {
            try? await appState.removeDestination(destination.id)
            dismiss()
        }
    }
}

// MARK: - Edit Destination Sheet

struct EditDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: DestinationRecord

    var body: some View {
        NavigationStack {
            Group {
                switch destination.type {
                case .s3:
                    EditS3DestinationForm(destination: destination)
                case .smb:
                    EditSMBDestinationForm(destination: destination)
                default:
                    Text("Unsupported destination type")
                }
            }
            .navigationTitle("Edit Destination")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 750)
    }
}

// MARK: - Edit S3 Destination Form

struct EditS3DestinationForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let destination: DestinationRecord

    @State private var selectedProvider: S3Configuration.S3Provider = .custom
    @State private var name = ""
    @State private var endpointURL = ""
    @State private var region = ""
    @State private var bucketName = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var pathPrefix = ""
    @State private var storageClass: S3Configuration.StorageClass = .standard
    @State private var encryption: S3Configuration.ServerSideEncryption = .none
    @State private var usePathStyleAccess = false

    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult?
    @State private var errorMessage: String?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(S3Configuration.S3Provider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: selectedProvider) { _, newValue in
                    updateEndpointForProvider(newValue)
                }
            }

            Section("Basic Configuration") {
                TextField("Display Name", text: $name)
                TextField("Endpoint URL", text: $endpointURL)

                if selectedProvider == .ovh {
                    Picker("Region", selection: $region) {
                        ForEach(S3Configuration.OVHRegion.allCases, id: \.self) { ovhRegion in
                            Text(ovhRegion.displayName).tag(ovhRegion.rawValue)
                        }
                    }
                    .onChange(of: region) { _, newValue in
                        endpointURL = "https://s3.\(newValue).io.cloud.ovh.net"
                    }
                } else {
                    TextField("Region", text: $region)
                }

                TextField("Bucket Name", text: $bucketName)
            }

            Section("Credentials") {
                TextField("Access Key ID", text: $accessKeyID)
                SecureField("Secret Access Key", text: $secretAccessKey)
                    .overlay(alignment: .trailing) {
                        if secretAccessKey.isEmpty {
                            Text("(unchanged)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 4)
                        }
                    }
            }

            Section("Advanced") {
                TextField("Path Prefix (optional)", text: $pathPrefix)

                Toggle("Use Path-Style Access", isOn: $usePathStyleAccess)

                Picker("Storage Class", selection: $storageClass) {
                    ForEach(S3Configuration.StorageClass.allCases, id: \.self) { sc in
                        Text(sc.description).tag(sc)
                    }
                }

                Picker("Server-Side Encryption", selection: $encryption) {
                    ForEach(S3Configuration.ServerSideEncryption.allCases, id: \.self) { enc in
                        Text(enc.description).tag(enc)
                    }
                }
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isValid)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let error):
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button("Save Changes") {
                    saveDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSaving)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadConfiguration()
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !endpointURL.isEmpty && !region.isEmpty &&
        !bucketName.isEmpty && !accessKeyID.isEmpty
    }

    private func loadConfiguration() {
        name = destination.name

        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(S3Configuration.self, from: destination.configJSON)

            selectedProvider = config.provider
            endpointURL = config.endpointURL
            region = config.region
            bucketName = config.bucketName
            accessKeyID = config.accessKeyID
            secretAccessKey = config.secretAccessKey
            pathPrefix = config.pathPrefix
            storageClass = config.storageClass
            encryption = config.serverSideEncryption
            usePathStyleAccess = config.usePathStyleAccess
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
        }
    }

    private func updateEndpointForProvider(_ provider: S3Configuration.S3Provider) {
        switch provider {
        case .aws:
            endpointURL = "https://s3.\(region).amazonaws.com"
        case .minio:
            if endpointURL.isEmpty || !endpointURL.contains("localhost") {
                endpointURL = "http://localhost:9000"
            }
        case .ovh:
            endpointURL = "https://s3.\(region).io.cloud.ovh.net"
        case .backblaze:
            endpointURL = "https://s3.\(region).backblazeb2.com"
        case .wasabi:
            endpointURL = "https://s3.\(region).wasabisys.com"
        case .custom:
            break
        }

        usePathStyleAccess = provider.requiresPathStyle
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        errorMessage = nil

        Task {
            do {
                let config = buildConfiguration()
                _ = try await appState.testDestination(config)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func saveDestination() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let config = buildConfiguration()
                try await appState.updateDestination(destination.id, config: config)
                dismiss()
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    private func buildConfiguration() -> S3Configuration {
        S3Configuration(
            id: destination.id,
            name: name,
            endpointURL: endpointURL,
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            pathPrefix: pathPrefix,
            usePathStyleAccess: usePathStyleAccess,
            storageClass: storageClass,
            serverSideEncryption: encryption,
            provider: selectedProvider,
            createdAt: destination.createdAt
        )
    }
}

// MARK: - Edit SMB Destination Form

struct EditSMBDestinationForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let destination: DestinationRecord

    // Server settings
    @State private var name = ""
    @State private var serverAddress = ""
    @State private var port = "445"
    @State private var shareName = ""
    @State private var pathPrefix = ""

    // Authentication
    @State private var authType: SMBConfiguration.SMBAuthType = .credentials
    @State private var username = ""
    @State private var password = ""
    @State private var domain = ""

    // Share discovery
    @State private var discoveredShares: [String] = []
    @State private var isDiscovering = false
    @State private var discoveryError: String?

    // State
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult?
    @State private var errorMessage: String?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Display Name", text: $name)
                    .textContentType(.name)

                TextField("Server Address", text: $serverAddress, prompt: Text("192.168.1.100 or nas.local"))
                    .textContentType(.URL)

                TextField("Port", text: $port)
                    .frame(width: 100)
            }

            Section("Share") {
                HStack {
                    if discoveredShares.isEmpty {
                        TextField("Share Name", text: $shareName)
                    } else {
                        Picker("Share Name", selection: $shareName) {
                            Text("Select a share...").tag("")
                            ForEach(discoveredShares, id: \.self) { share in
                                Text(share).tag(share)
                            }
                        }
                    }

                    Button(action: discoverShares) {
                        if isDiscovering {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverAddress.isEmpty || isDiscovering)
                    .help("Discover available shares")
                }

                if let error = discoveryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Path Prefix (optional)", text: $pathPrefix, prompt: Text("Subfolder within share"))
            }

            Section("Authentication") {
                Picker("Authentication", selection: $authType) {
                    ForEach(SMBConfiguration.SMBAuthType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)

                if authType == .credentials {
                    TextField("Username", text: $username)
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .overlay(alignment: .trailing) {
                            if password.isEmpty {
                                Text("(unchanged)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 4)
                            }
                        }

                    TextField("Domain (optional)", text: $domain, prompt: Text("WORKGROUP"))
                }
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isValid)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let error):
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button("Save Changes") {
                    saveDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSaving)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadConfiguration()
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !serverAddress.isEmpty && !shareName.isEmpty &&
        (authType == .guest || !username.isEmpty)
    }

    private func loadConfiguration() {
        name = destination.name

        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(SMBConfiguration.self, from: destination.configJSON)

            serverAddress = config.serverAddress
            port = String(config.port)
            shareName = config.shareName
            pathPrefix = config.pathPrefix
            authType = config.authType
            username = config.username
            password = config.password
            domain = config.domain
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
        }
    }

    private func discoverShares() {
        isDiscovering = true
        discoveryError = nil

        Task {
            do {
                let shares = try await SMBDestinationService.discoverShares(
                    server: serverAddress,
                    username: authType == .credentials ? username : nil,
                    password: authType == .credentials ? password : nil
                )

                await MainActor.run {
                    discoveredShares = shares
                    if shares.isEmpty {
                        discoveryError = "No shares found on server"
                    }
                }
            } catch {
                await MainActor.run {
                    discoveryError = "Discovery failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                isDiscovering = false
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        errorMessage = nil

        Task {
            do {
                let config = buildConfiguration()
                _ = try await appState.testSMBDestination(config)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func saveDestination() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let config = buildConfiguration()
                try await appState.updateSMBDestination(destination.id, config: config)
                dismiss()
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    private func buildConfiguration() -> SMBConfiguration {
        SMBConfiguration(
            id: destination.id,
            name: name,
            serverAddress: serverAddress,
            shareName: shareName,
            port: Int(port) ?? 445,
            pathPrefix: pathPrefix,
            authType: authType,
            username: username,
            password: password,
            domain: domain,
            createdAt: destination.createdAt
        )
    }
}

#Preview {
    DestinationsView()
        .environment(AppState())
        .frame(width: 800, height: 600)
}
