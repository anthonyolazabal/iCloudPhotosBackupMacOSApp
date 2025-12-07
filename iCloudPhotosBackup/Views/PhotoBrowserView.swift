import SwiftUI
import OSLog

// MARK: - Photo Browser View

struct PhotoBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let destination: DestinationRecord

    @State private var allFiles: [RemoteFileMetadata] = []
    @State private var displayedFiles: [RemoteFileMetadata] = []
    @State private var folders: [String] = []
    @State private var currentPath: String = ""
    @State private var pathComponents: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFile: RemoteFileMetadata?
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var s3Service: S3DestinationService?

    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "PhotoBrowser")

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case nameAsc = "Name A-Z"
        case nameDesc = "Name Z-A"
        case sizeDesc = "Largest First"
        case sizeAsc = "Smallest First"
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView

                Divider()

                // Breadcrumb navigation
                if !pathComponents.isEmpty {
                    BreadcrumbNavigationView(
                        components: pathComponents,
                        onNavigate: { navigateToPathIndex($0) }
                    )
                    Divider()
                }

                // Content
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if allFiles.isEmpty && folders.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
            .navigationTitle("Browse Photos - \(destination.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .task {
            await initializeAndLoadFiles()
        }
        .sheet(item: $selectedFile) { file in
            if let service = s3Service {
                PhotoPreviewView(file: file, destination: destination, s3Service: service)
            }
        }
    }

    // MARK: - Subviews

    private var toolbarView: some View {
        HStack(spacing: 16) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 300)

            Spacer()

            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 150)

            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            // Refresh button
            Button(action: { Task { await loadFiles() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)

            // Stats
            Text("\(filteredFiles.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading files...")
                .font(.headline)
            Text("This may take a moment for large libraries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Failed to load files")
                .font(.title2)
                .fontWeight(.medium)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Retry") {
                Task { await loadFiles() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No photos found")
                .font(.title2)
                .fontWeight(.medium)

            Text(currentPath.isEmpty
                 ? "This destination has no backed up photos yet"
                 : "This folder is empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Folders section
                if !folders.isEmpty {
                    foldersSection
                }

                // Files section
                if !filteredFiles.isEmpty {
                    filesSection
                }
            }
            .padding()
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)], spacing: 12) {
                ForEach(folders, id: \.self) { folder in
                    FolderItemView(name: folder) {
                        navigateToFolder(folder)
                    }
                }
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files")
                .font(.headline)
                .foregroundStyle(.secondary)

            if viewMode == .grid {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(sortedFiles) { file in
                        PhotoGridItemView(
                            file: file,
                            s3Service: s3Service,
                            onTap: { selectedFile = file }
                        )
                    }
                }
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(sortedFiles) { file in
                        PhotoListItemView(file: file) {
                            selectedFile = file
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredFiles: [RemoteFileMetadata] {
        if searchText.isEmpty {
            return displayedFiles
        }
        return displayedFiles.filter {
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sortedFiles: [RemoteFileMetadata] {
        switch sortOrder {
        case .dateDesc:
            return filteredFiles.sorted { $0.modifiedDate > $1.modifiedDate }
        case .dateAsc:
            return filteredFiles.sorted { $0.modifiedDate < $1.modifiedDate }
        case .nameAsc:
            return filteredFiles.sorted { $0.filename.localizedCompare($1.filename) == .orderedAscending }
        case .nameDesc:
            return filteredFiles.sorted { $0.filename.localizedCompare($1.filename) == .orderedDescending }
        case .sizeDesc:
            return filteredFiles.sorted { $0.size > $1.size }
        case .sizeAsc:
            return filteredFiles.sorted { $0.size < $1.size }
        }
    }

    // MARK: - Actions

    private func initializeAndLoadFiles() async {
        do {
            let config = try JSONDecoder().decode(S3Configuration.self, from: destination.configJSON)
            let service = try S3DestinationService(configuration: config)
            try await service.connect()

            await MainActor.run {
                self.s3Service = service
            }

            await loadFiles()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadFiles() async {
        guard let service = s3Service else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let files = try await service.listFiles(in: currentPath)

            await MainActor.run {
                processFiles(files)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func processFiles(_ files: [RemoteFileMetadata]) {
        allFiles = files
        var folderSet = Set<String>()
        var fileList: [RemoteFileMetadata] = []

        let prefix = currentPath.isEmpty ? "" : currentPath + "/"

        for file in files {
            // Get relative path from current directory
            let relativePath: String
            if prefix.isEmpty {
                relativePath = file.path
            } else if file.path.hasPrefix(prefix) {
                relativePath = String(file.path.dropFirst(prefix.count))
            } else {
                continue
            }

            if relativePath.contains("/") {
                // It's in a subfolder - extract first folder name
                if let folderName = relativePath.split(separator: "/").first {
                    folderSet.insert(String(folderName))
                }
            } else if !relativePath.isEmpty {
                // It's a file in the current directory
                fileList.append(file)
            }
        }

        folders = folderSet.sorted()
        displayedFiles = fileList
    }

    private func navigateToFolder(_ folder: String) {
        if currentPath.isEmpty {
            currentPath = folder
        } else {
            currentPath = currentPath + "/" + folder
        }
        pathComponents = currentPath.split(separator: "/").map(String.init)
        Task { await loadFiles() }
    }

    private func navigateToPathIndex(_ index: Int) {
        if index < 0 {
            currentPath = ""
            pathComponents = []
        } else {
            pathComponents = Array(pathComponents.prefix(index + 1))
            currentPath = pathComponents.joined(separator: "/")
        }
        Task { await loadFiles() }
    }
}

// MARK: - Breadcrumb Navigation View

struct BreadcrumbNavigationView: View {
    let components: [String]
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Root
                Button(action: { onNavigate(-1) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                        Text("Root")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button(action: { onNavigate(index) }) {
                        Text(component)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(index == components.count - 1
                                        ? Color.blue.opacity(0.2)
                                        : Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Folder Item View

struct FolderItemView: View {
    let name: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo Grid Item View

struct PhotoGridItemView: View {
    let file: RemoteFileMetadata
    let s3Service: S3DestinationService?
    let onTap: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var loadError = false

    private let thumbnailSize = CGSize(width: 200, height: 200)

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Thumbnail area
                ZStack {
                    Color(.controlBackgroundColor)

                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if loadError {
                        VStack(spacing: 4) {
                            Image(systemName: file.isVideo ? "video.fill" : "photo.fill")
                                .font(.title)
                            Text(file.isVideo ? "Video" : "Image")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    // Video badge
                    if file.isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .padding(8)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .clipped()

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard file.isImage, let service = s3Service else {
            isLoading = false
            loadError = true
            return
        }

        // Check cache first
        if let cached = await ImageCacheService.shared.getThumbnail(for: file.path, size: thumbnailSize) {
            await MainActor.run {
                thumbnail = cached
                isLoading = false
            }
            return
        }

        // Download and generate thumbnail
        do {
            let data = try await service.downloadFile(at: file.path) { _ in }

            if let image = NSImage(data: data) {
                let thumb = image.thumbnail(maxSize: 200)

                // Cache it
                await ImageCacheService.shared.cacheThumbnail(thumb, for: file.path, size: thumbnailSize)

                await MainActor.run {
                    thumbnail = thumb
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    loadError = true
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                loadError = true
                isLoading = false
            }
        }
    }
}

// MARK: - Photo List Item View

struct PhotoListItemView: View {
    let file: RemoteFileMetadata
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: file.isVideo ? "video.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundStyle(file.isVideo ? .purple : .blue)
                    .frame(width: 40)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(file.formattedSize)
                        Text("•")
                        Text(file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PhotoBrowserView(destination: DestinationRecord(
        name: "Test Destination",
        type: .s3,
        configJSON: Data()
    ))
    .environment(AppState())
    .frame(width: 1000, height: 800)
}
