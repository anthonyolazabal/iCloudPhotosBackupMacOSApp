import SwiftUI
import OSLog
import AVKit
import UniformTypeIdentifiers

// MARK: - Photo Preview View

struct PhotoPreviewView: View {
    let file: RemoteFileMetadata
    let destination: DestinationRecord
    let s3Service: S3DestinationService

    @Environment(\.dismiss) private var dismiss

    @State private var image: NSImage?
    @State private var videoPlayer: AVPlayer?
    @State private var isLoading = true
    @State private var loadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var zoomScale: CGFloat = 1.0
    @State private var showMetadata = true
    @State private var isSaving = false
    @State private var saveProgress: Double = 0
    @State private var saveError: String?
    @State private var showingSaveSuccess = false

    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "PhotoPreview")

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            headerView

            Divider()

            // Content area
            HStack(spacing: 0) {
                // Main preview area
                previewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Metadata sidebar
                if showMetadata {
                    Divider()
                    metadataSidebar
                        .frame(width: 280)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await loadContent()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Text(file.filename)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Zoom controls (for images)
            if file.isImage && image != nil {
                HStack(spacing: 8) {
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(zoomScale <= 0.25)

                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 50)

                    Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(zoomScale >= 4.0)

                    Button(action: { zoomScale = 1.0 }) {
                        Text("Fit")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
            }

            // Download button
            if isSaving {
                HStack(spacing: 8) {
                    ProgressView(value: saveProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 100)
                    Text("\(Int(saveProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
            } else {
                Button(action: { saveToDownloads() }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .help("Save to Downloads folder")
            }

            // Toggle metadata
            Button(action: { withAnimation { showMetadata.toggle() } }) {
                Image(systemName: showMetadata ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(showMetadata ? .none : .slash)
            }
            .buttonStyle(.bordered)
            .help("Toggle metadata panel")
        }
        .padding()
        .alert("File Saved", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file has been saved successfully.")
        }
        .alert("Save Error", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            if let error = saveError {
                Text(error)
            }
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            Color(.windowBackgroundColor)

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let image = image {
                imagePreview(image)
            } else if let player = videoPlayer {
                videoPreview(player)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: loadProgress) {
                Text("Downloading...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .frame(width: 300)

            Text("\(Int(loadProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(file.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Failed to load file")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Retry") {
                Task { await loadContent() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func imagePreview(_ image: NSImage) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(zoomScale)
                .frame(
                    width: zoomScale > 1 ? image.size.width * zoomScale : nil,
                    height: zoomScale > 1 ? image.size.height * zoomScale : nil
                )
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / (zoomScale > 0 ? zoomScale : 1)
                    zoomScale = min(4.0, max(0.25, zoomScale * delta))
                }
        )
    }

    private func videoPreview(_ player: AVPlayer) -> some View {
        VideoPlayer(player: player)
            .onDisappear {
                player.pause()
            }
    }

    // MARK: - Metadata Sidebar

    private var metadataSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // File icon
                VStack(spacing: 12) {
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 150)
                            .cornerRadius(8)
                    } else {
                        Image(systemName: file.isVideo ? "video.fill" : "photo.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(file.isVideo ? .purple : .blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top)

                Divider()

                // File information
                metadataSection("File Information") {
                    metadataRow("Name", file.filename)
                    metadataRow("Size", file.formattedSize)
                    metadataRow("Type", file.isVideo ? "Video" : "Image")
                    metadataRow("Modified", file.modifiedDate.formatted(date: .long, time: .shortened))
                }

                Divider()

                // Location information
                metadataSection("Location") {
                    metadataRow("Destination", destination.name)
                    metadataRow("Path", file.path)
                }

                if let checksum = file.checksum {
                    Divider()

                    metadataSection("Verification") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ETag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(checksum)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private func metadataSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    // MARK: - Load Content

    private func loadContent() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            loadProgress = 0
        }

        do {
            // Check cache first for images
            if file.isImage {
                if let cached = await ImageCacheService.shared.getFullImage(for: file.path) {
                    await MainActor.run {
                        self.image = cached
                        isLoading = false
                    }
                    return
                }
            }

            // Download the file
            let data = try await s3Service.downloadFile(at: file.path) { progress in
                Task { @MainActor in
                    self.loadProgress = progress
                }
            }

            if file.isImage {
                if let nsImage = NSImage(data: data) {
                    // Cache the full image
                    await ImageCacheService.shared.cacheFullImage(nsImage, for: file.path)

                    await MainActor.run {
                        self.image = nsImage
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Unable to decode image data"
                        isLoading = false
                    }
                }
            } else if file.isVideo {
                // For videos, save to temp file and create player
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(file.path.split(separator: ".").last.map(String.init) ?? "mp4")

                try data.write(to: tempURL)

                await MainActor.run {
                    let player = AVPlayer(url: tempURL)
                    self.videoPlayer = player
                    isLoading = false
                    player.play()
                }
            } else {
                await MainActor.run {
                    errorMessage = "Unsupported file type"
                    isLoading = false
                }
            }

        } catch {
            logger.error("Failed to load file: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Save to Downloads

    private func saveToDownloads() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = file.isVideo
            ? [.movie, .video, .mpeg4Movie, .quickTimeMovie]
            : [.image, .jpeg, .png, .heic, .tiff]
        panel.nameFieldStringValue = file.filename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save \(file.isVideo ? "Video" : "Photo")"
        panel.message = "Choose a location to save the file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await downloadAndSave(to: url)
                }
            }
        }
    }

    private func downloadAndSave(to url: URL) async {
        await MainActor.run {
            isSaving = true
            saveProgress = 0
            saveError = nil
        }

        do {
            // Download the file from S3
            let data = try await s3Service.downloadFile(at: file.path) { progress in
                Task { @MainActor in
                    self.saveProgress = progress
                }
            }

            // Write to the selected location
            try data.write(to: url)

            logger.info("File saved successfully to: \(url.path)")

            await MainActor.run {
                isSaving = false
                showingSaveSuccess = true
            }
        } catch {
            logger.error("Failed to save file: \(error.localizedDescription)")
            await MainActor.run {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}

#Preview {
    PhotoPreviewView(
        file: RemoteFileMetadata(
            path: "photos/2024/test.jpg",
            size: 1024 * 1024 * 5,
            modifiedDate: Date(),
            checksum: "abc123"
        ),
        destination: DestinationRecord(
            name: "Test Destination",
            type: .s3,
            configJSON: Data()
        ),
        s3Service: try! S3DestinationService(configuration: S3Configuration(
            id: UUID(),
            name: "Test",
            endpointURL: "https://s3.us-east-1.amazonaws.com",
            region: "us-east-1",
            bucketName: "test",
            accessKeyID: "test",
            secretAccessKey: "test",
            pathPrefix: "",
            usePathStyleAccess: false,
            storageClass: .standard,
            serverSideEncryption: .none,
            httpProxyURL: nil,
            provider: .aws,
            createdAt: Date()
        ))
    )
    .frame(width: 1000, height: 700)
}
