import SwiftUI

// MARK: - Documentation View

struct DocumentationView: View {
    @State private var selectedSection: DocSection = .gettingStarted
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            // Sidebar with sections
            sidebarView
                .frame(minWidth: 200, maxWidth: 250)

            // Content area
            ScrollView {
                contentView
                    .padding(24)
                    .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Documentation")
                    .font(.title2)
                    .fontWeight(.bold)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding()

            Divider()

            // Sections list
            List(filteredSections, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var filteredSections: [DocSection] {
        if searchText.isEmpty {
            return DocSection.allCases
        }
        return DocSection.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Section header
            VStack(alignment: .leading, spacing: 8) {
                Label(selectedSection.title, systemImage: selectedSection.icon)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(selectedSection.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Section content
            selectedSection.contentView
        }
    }
}

// MARK: - Documentation Sections

enum DocSection: String, CaseIterable {
    case gettingStarted
    case destinations
    case backupJobs
    case scheduledBackups
    case verification
    case browsing
    case history
    case settings
    case troubleshooting
    case faq

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .destinations: return "Destinations"
        case .backupJobs: return "Backup Jobs"
        case .scheduledBackups: return "Scheduled Backups"
        case .verification: return "Verification"
        case .browsing: return "Browsing Photos"
        case .history: return "History"
        case .settings: return "Settings"
        case .troubleshooting: return "Troubleshooting"
        case .faq: return "FAQ"
        }
    }

    var subtitle: String {
        switch self {
        case .gettingStarted: return "Learn the basics of iCloud Photos Backup"
        case .destinations: return "Configure where your photos are backed up"
        case .backupJobs: return "Run and manage backup operations"
        case .scheduledBackups: return "Automate your backups with schedules"
        case .verification: return "Verify backup integrity and find gaps"
        case .browsing: return "Browse and download your backed up photos"
        case .history: return "View past backup and verification history"
        case .settings: return "Configure application settings"
        case .troubleshooting: return "Solve common issues"
        case .faq: return "Frequently asked questions"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: return "star.fill"
        case .destinations: return "externaldrive.connected.to.line.below"
        case .backupJobs: return "arrow.clockwise.circle"
        case .scheduledBackups: return "calendar.badge.clock"
        case .verification: return "checkmark.shield"
        case .browsing: return "photo.on.rectangle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .faq: return "questionmark.circle"
        }
    }

    var content: String {
        switch self {
        case .gettingStarted:
            return "Welcome to iCloud Photos Backup. This app helps you backup your iCloud Photos library to S3-compatible storage or SMB network shares."
        case .destinations:
            return "Configure storage destinations including S3-compatible cloud storage (AWS S3, OVH, Wasabi) and SMB network shares (NAS, Windows shares)."
        case .backupJobs:
            return "Run backup jobs to sync your photos to your configured destinations."
        case .scheduledBackups:
            return "Set up automated backups that run on a schedule."
        case .verification:
            return "Verify that your backups are complete and uncorrupted."
        case .browsing:
            return "Browse your backed up photos and download them when needed."
        case .history:
            return "View the history of your backup and verification operations."
        case .settings:
            return "Configure application settings and preferences."
        case .troubleshooting:
            return "Common issues and their solutions."
        case .faq:
            return "Frequently asked questions about the application."
        }
    }

    @ViewBuilder
    var contentView: some View {
        switch self {
        case .gettingStarted:
            GettingStartedContent()
        case .destinations:
            DestinationsDocContent()
        case .backupJobs:
            BackupJobsDocContent()
        case .scheduledBackups:
            ScheduledBackupsDocContent()
        case .verification:
            VerificationDocContent()
        case .browsing:
            BrowsingDocContent()
        case .history:
            HistoryDocContent()
        case .settings:
            SettingsDocContent()
        case .troubleshooting:
            TroubleshootingContent()
        case .faq:
            FAQContent()
        }
    }
}

// MARK: - Documentation Content Views

struct GettingStartedContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Welcome to iCloud Photos Backup! This application allows you to backup your iCloud Photos library to S3-compatible cloud storage or network shares (SMB), giving you an independent backup of your precious memories."
            )

            DocHeading("Quick Start Guide")

            DocNumberedList([
                "**Add a Destination**: Go to the Destinations tab and click \"Add Destination\" to configure your storage (S3 or SMB network share).",
                "**Run Your First Backup**: Navigate to Backup Jobs and click \"New Backup Job\" to start backing up your photos.",
                "**Set Up Scheduled Backups**: For automatic backups, go to Scheduled Jobs and create a schedule that works for you.",
                "**Verify Your Backups**: Use the Verification tab to ensure your backups are complete and uncorrupted."
            ])

            DocHeading("Key Features")

            DocBulletList([
                "Backup photos and videos from your iCloud Photos library",
                "Support for multiple S3-compatible storage providers",
                "Support for SMB/CIFS network shares (NAS devices, Windows shares)",
                "Scheduled automatic backups",
                "Backup verification with checksum validation",
                "Browse and download backed up photos",
                "Detailed logging and history tracking"
            ])

            DocHeading("System Requirements")

            DocBulletList([
                "macOS 14.0 (Sonoma) or later",
                "Photos app with iCloud Photos enabled",
                "Internet connection for cloud storage access (S3)",
                "Network access for SMB shares",
                "S3-compatible storage account or SMB network share"
            ])

            DocTip("For best results, ensure your Mac has access to your full iCloud Photos library by enabling 'Download Originals to this Mac' in Photos preferences.")
        }
    }
}

struct DestinationsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Destinations are the storage locations where your photos will be backed up. The app supports S3-compatible cloud storage and SMB network shares."
            )

            DocHeading("Destination Types")

            DocSubheading("S3 Compatible Storage")
            DocParagraph("Cloud storage using the S3 protocol. Includes AWS S3, OVH Object Storage, Wasabi, Backblaze B2, and any S3-compatible provider.")

            DocSubheading("SMB Network Shares")
            DocParagraph("Local network storage using the SMB/CIFS protocol. Includes NAS devices (Synology, QNAP), Windows shared folders, and macOS/Linux Samba shares.")

            DocHeading("Adding an S3 Destination")

            DocNumberedList([
                "Click \"Add Destination\" in the Destinations tab",
                "Select \"S3 Compatible Storage\" at the top",
                "Choose your storage provider (AWS S3, OVH, or Custom S3)",
                "Enter your credentials and bucket information",
                "Test the connection to verify your settings",
                "Click \"Add Destination\""
            ])

            DocHeading("Adding an SMB Destination")

            DocNumberedList([
                "Click \"Add Destination\" in the Destinations tab",
                "Select \"Network Share (SMB)\" at the top",
                "Enter the server address (IP or hostname)",
                "Click the refresh button to discover available shares, or enter the share name manually",
                "Choose authentication type (Guest or Username/Password)",
                "Enter credentials if using authentication",
                "Test the connection to verify access",
                "Click \"Add Destination\""
            ])

            DocHeading("S3 Providers")

            DocSubheading("AWS S3")
            DocParagraph("Amazon's Simple Storage Service. Use your AWS access key and secret key, specify your region and bucket name.")

            DocSubheading("OVH Object Storage")
            DocParagraph("OVH's S3-compatible storage. Requires your OVH credentials and the appropriate endpoint URL for your region.")

            DocSubheading("Custom S3-Compatible")
            DocParagraph("Any S3-compatible storage like Wasabi, Backblaze B2, MinIO, etc. Enter the custom endpoint URL and credentials.")

            DocHeading("SMB Configuration Options")

            DocDefinitionList([
                ("Server Address", "IP address (e.g., 192.168.1.100) or hostname (e.g., nas.local)"),
                ("Port", "SMB port, typically 445 (default)"),
                ("Share Name", "The name of the shared folder on the server"),
                ("Path Prefix", "Optional subfolder within the share"),
                ("Authentication", "Guest access (no credentials) or Username & Password"),
                ("Username", "Account username for authenticated access"),
                ("Password", "Account password for authenticated access"),
                ("Domain", "Optional workgroup or domain name (e.g., WORKGROUP)")
            ])

            DocHeading("S3 Configuration Options")

            DocDefinitionList([
                ("Endpoint URL", "The S3 API endpoint for your provider"),
                ("Region", "The geographic region of your bucket"),
                ("Bucket Name", "The name of your storage bucket"),
                ("Access Key ID", "Your S3 access key identifier"),
                ("Secret Access Key", "Your S3 secret access key"),
                ("Path Prefix", "Optional folder path within the bucket"),
                ("Storage Class", "The storage tier to use (Standard, Infrequent Access, etc.)")
            ])

            DocTip("Use the share discovery button to automatically find available shares on your SMB server. This requires the server to be reachable on your network.")

            DocWarning("Keep your credentials secure. They are stored locally in the application's database. Ensure your Mac has proper security measures like FileVault enabled.")
        }
    }
}

struct BackupJobsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Backup jobs are the operations that sync your photos from iCloud Photos to your configured destinations."
            )

            DocHeading("Running a Backup")

            DocSubheading("Quick Backup")
            DocParagraph("Use the quick backup cards to start an immediate backup with preset filters like 'Full Library', 'Last 30 Days', or 'Last Year'.")

            DocSubheading("Custom Backup")
            DocNumberedList([
                "Click \"New Backup Job\"",
                "Select the destination",
                "Choose a date range filter",
                "Click \"Start Backup\""
            ])

            DocHeading("During Backup")

            DocParagraph("While a backup is running, you'll see:")
            DocBulletList([
                "Progress bar showing completion percentage",
                "Number of photos processed vs total",
                "Current photo being uploaded",
                "Transfer speed statistics",
                "Pause, resume, or cancel controls"
            ])

            DocHeading("Backup Filters")

            DocDefinitionList([
                ("Full Library", "Backup all photos in your library"),
                ("Last 30 Days", "Photos from the past month"),
                ("Last Year", "Photos from the past 12 months"),
                ("Custom Range", "Specify exact start and end dates")
            ])

            DocTip("The app only uploads photos that haven't been backed up yet, making subsequent backups much faster.")
        }
    }
}

struct ScheduledBackupsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Scheduled backups allow you to automate your backup process, ensuring your photos are regularly backed up without manual intervention."
            )

            DocHeading("Creating a Schedule")

            DocNumberedList([
                "Go to the Scheduled Jobs tab",
                "Click \"Add Schedule\"",
                "Configure the schedule settings",
                "Enable the schedule"
            ])

            DocHeading("Schedule Types")

            DocDefinitionList([
                ("Daily", "Run the backup every day at a specified time"),
                ("Weekly", "Run on specific days of the week"),
                ("Interval", "Run every X hours (e.g., every 6 hours)"),
                ("One-Time", "Run once at a specific date and time")
            ])

            DocHeading("Schedule Options")

            DocBulletList([
                "**Destination**: Which storage to backup to",
                "**Filter**: Which photos to include (Full Library, Last 30 Days, etc.)",
                "**Enabled/Disabled**: Toggle the schedule on or off",
                "**Run Now**: Manually trigger the scheduled job immediately"
            ])

            DocHeading("Best Practices")

            DocBulletList([
                "Schedule backups during off-peak hours for better performance",
                "Use daily backups for active photo libraries",
                "Consider weekly full backups combined with daily incremental backups",
                "Monitor the History tab to ensure schedules are running successfully"
            ])

            DocTip("You can click 'Run Now' on any scheduled job to trigger it immediately without waiting for the next scheduled time.")
        }
    }
}

struct VerificationDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Verification ensures your backups are complete and the files are not corrupted. Regular verification gives you confidence in your backup integrity."
            )

            DocHeading("Verification Types")

            DocSubheading("Quick Check")
            DocParagraph("Randomly verifies a sample of 10 photos. Fast way to spot-check your backup integrity.")

            DocSubheading("Full Verification")
            DocParagraph("Verifies every synced photo by checking file size against the remote copy. Thorough but time-consuming for large libraries.")

            DocSubheading("Gap Detection")
            DocParagraph("Finds photos in your library that haven't been backed up yet. Useful for identifying missing backups.")

            DocHeading("Verification Process")

            DocParagraph("During verification, the app:")
            DocBulletList([
                "Connects to your storage destination",
                "Checks that each backed up file exists",
                "Validates file sizes match expected values",
                "Reports any missing or corrupted files"
            ])

            DocHeading("Understanding Results")

            DocDefinitionList([
                ("Verified", "File exists and size matches - backup is good"),
                ("Mismatch", "File exists but size differs - may be corrupted"),
                ("Missing", "File not found on remote storage"),
                ("Error", "Could not verify due to connection or other issues")
            ])

            DocHeading("After Verification")

            DocParagraph("If issues are found:")
            DocBulletList([
                "Missing files will be re-uploaded on the next backup",
                "Corrupted files can be deleted and re-synced",
                "Check the verification logs for detailed information"
            ])

            DocTip("Run a quick verification after each backup to catch any issues early.")
        }
    }
}

struct BrowsingDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "The photo browser lets you view and download your backed up photos directly from your cloud storage."
            )

            DocHeading("Opening the Browser")

            DocNumberedList([
                "Go to the Destinations tab",
                "Click \"Browse\" on any destination",
                "Wait for the file list to load"
            ])

            DocHeading("Navigation")

            DocBulletList([
                "Use the breadcrumb navigation to move between folders",
                "Click on folders to open them",
                "Click on photos to preview them",
                "Use the search bar to find specific files"
            ])

            DocHeading("View Options")

            DocDefinitionList([
                ("Grid View", "Shows photo thumbnails in a grid layout"),
                ("List View", "Shows files in a detailed list with metadata"),
                ("Sort Order", "Sort by date, name, or size")
            ])

            DocHeading("Photo Preview")

            DocParagraph("When you click on a photo:")
            DocBulletList([
                "Full resolution image is downloaded and displayed",
                "Use zoom controls or pinch to zoom",
                "View metadata in the sidebar (size, date, path)",
                "Videos can be played directly in the preview"
            ])

            DocHeading("Downloading Photos")

            DocParagraph("To save a photo to your Mac:")
            DocNumberedList([
                "Open the photo in preview",
                "Click the \"Download\" button in the header",
                "Choose where to save the file",
                "Wait for the download to complete"
            ])

            DocTip("Thumbnails are cached locally for faster browsing on subsequent visits.")
        }
    }
}

struct HistoryDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "The History tab shows a record of all your backup and verification operations."
            )

            DocHeading("Sync Jobs History")

            DocParagraph("Each sync job entry shows:")
            DocBulletList([
                "Destination name",
                "Start time and duration",
                "Number of photos synced",
                "Number of photos failed (if any)",
                "Data transferred"
            ])

            DocHeading("Verification History")

            DocParagraph("Switch to the Verifications tab to see:")
            DocBulletList([
                "Verification type (Quick, Full, Incremental)",
                "Verification results (verified, missing, mismatches)",
                "Success rate percentage"
            ])

            DocHeading("Viewing Logs")

            DocNumberedList([
                "Click the menu button (...) on any job",
                "Select \"View Logs\"",
                "Browse through detailed log entries",
                "Use filters to find specific log levels or categories",
                "Export logs to a text file if needed"
            ])

            DocHeading("Managing History")

            DocBulletList([
                "Delete individual jobs using the menu",
                "Clear all history using the \"Clear All\" button",
                "History older than 14 days is automatically cleaned up"
            ])
        }
    }
}

struct SettingsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocParagraph(
                "Configure application behavior and preferences in the Settings tab."
            )

            DocHeading("Export Settings")

            DocDefinitionList([
                ("Include Videos", "Whether to backup video files along with photos"),
                ("Include RAW", "Whether to include RAW photo formats"),
                ("Include Screenshots", "Whether to backup screenshots"),
                ("Preserve Original Filename", "Keep the original filename or use a standardized format")
            ])

            DocHeading("Performance Settings")

            DocDefinitionList([
                ("Concurrent Uploads", "Number of simultaneous uploads (1-10)"),
                ("Chunk Size", "Size of upload chunks for large files")
            ])

            DocHeading("Organization")

            DocDefinitionList([
                ("Folder Structure", "How photos are organized in the destination (by date, by album, flat)"),
                ("Date Format", "Format for date-based folders (YYYY/MM, YYYY-MM-DD, etc.)")
            ])

            DocTip("Higher concurrent uploads can speed up backups but may use more bandwidth and system resources.")
        }
    }
}

struct TroubleshootingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocHeading("Common Issues")

            DocSubheading("S3 Connection Failed")
            DocParagraph("If you can't connect to your S3 destination:")
            DocBulletList([
                "Verify your credentials are correct",
                "Check that the endpoint URL is correct",
                "Ensure your bucket exists and you have access",
                "Check your internet connection",
                "Verify firewall settings allow S3 traffic"
            ])

            DocSubheading("SMB Connection Failed")
            DocParagraph("If you can't connect to your SMB network share:")
            DocBulletList([
                "Verify the server address is correct and reachable",
                "Ensure the SMB share exists on the server",
                "Check that your username and password are correct",
                "Verify you have permission to access the share",
                "Check that SMB port 445 is not blocked by firewall",
                "Try using the IP address instead of hostname",
                "Ensure the server is online and accessible on your network"
            ])

            DocSubheading("SMB Share Discovery Failed")
            DocParagraph("If you can't discover shares on the server:")
            DocBulletList([
                "Ensure the server address is correct",
                "Try authenticating first if using credentials",
                "Some servers disable share enumeration for security",
                "Enter the share name manually if discovery doesn't work"
            ])

            DocSubheading("SMB Mount Permission Denied")
            DocParagraph("If mounting the SMB share fails with permission errors:")
            DocBulletList([
                "Verify your user account has access to the share",
                "Check the share permissions on the server",
                "For domain environments, include the domain name",
                "Ensure the path prefix folder exists or the app can create it"
            ])

            DocSubheading("Backup Stuck or Slow")
            DocParagraph("If backups are taking too long:")
            DocBulletList([
                "Check your internet upload speed (for S3)",
                "Check your network speed (for SMB)",
                "Reduce concurrent uploads in Settings",
                "Ensure iCloud Photos has finished downloading originals",
                "Try backing up a smaller date range first",
                "For SMB, ensure your NAS is not under heavy load"
            ])

            DocSubheading("Photos Not Found")
            DocParagraph("If the app can't find your photos:")
            DocBulletList([
                "Grant Photos access when prompted",
                "Open System Settings > Privacy & Security > Photos",
                "Ensure iCloud Photos is enabled in the Photos app",
                "Enable 'Download Originals to this Mac' in Photos preferences"
            ])

            DocSubheading("Verification Failures")
            DocParagraph("If verification shows missing or mismatched files:")
            DocBulletList([
                "Run another backup to re-upload missing files",
                "Check storage provider dashboard for any issues",
                "Verify you have sufficient storage space",
                "Check the verification logs for specific errors"
            ])

            DocHeading("Getting More Help")

            DocParagraph("If you continue to experience issues:")
            DocBulletList([
                "Check the logs in the History tab for detailed error messages",
                "Export logs and include them when reporting issues",
                "Visit the project repository for updates and known issues"
            ])
        }
    }
}

struct FAQContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DocFAQItem(
                question: "Does this app upload my photos to Anthropic or any third party?",
                answer: "No. This app only backs up your photos to the storage destination you configure (S3 or SMB). Your photos never pass through any third-party servers."
            )

            DocFAQItem(
                question: "Will my photos be deleted from iCloud?",
                answer: "No. This app only creates a backup copy of your photos. Your original photos in iCloud Photos remain untouched."
            )

            DocFAQItem(
                question: "Can I backup to multiple destinations?",
                answer: "Yes! You can add multiple destinations (both S3 and SMB) and run backups to each one. This is great for having redundant backups."
            )

            DocFAQItem(
                question: "Should I use S3 or SMB for my backup?",
                answer: "S3 is ideal for cloud storage with unlimited scalability and off-site backup. SMB is great for local NAS devices where you want fast local network speeds and full control over your data. Many users use both for redundancy."
            )

            DocFAQItem(
                question: "What NAS devices work with SMB backup?",
                answer: "Any NAS that supports SMB/CIFS protocol works, including Synology, QNAP, Western Digital, Asustor, TrueNAS, and more. Windows shared folders and macOS/Linux Samba shares also work."
            )

            DocFAQItem(
                question: "How much storage do I need?",
                answer: "You'll need enough storage to hold copies of all the photos you want to backup. Check your iCloud Photos library size in Photos > About to estimate."
            )

            DocFAQItem(
                question: "Are my credentials stored securely?",
                answer: "Your credentials (S3 keys or SMB passwords) are stored locally in the application's database on your Mac. For additional security, enable FileVault disk encryption on your Mac. Encryption keys used by the app are stored in the macOS Keychain."
            )

            DocFAQItem(
                question: "Can I restore photos from my backup?",
                answer: "Yes. Use the Browse feature to view and download individual photos. For S3, you can also use any S3-compatible tool. For SMB, you can access the files directly from Finder."
            )

            DocFAQItem(
                question: "What happens if a backup is interrupted?",
                answer: "The app tracks which photos have been successfully backed up. When you run another backup, it will resume from where it left off, skipping already backed up photos."
            )

            DocFAQItem(
                question: "Does the SMB share stay mounted during backup?",
                answer: "Yes. The app mounts the SMB share when starting a backup and unmounts it when complete. This is handled automatically."
            )

            DocFAQItem(
                question: "Does the app backup albums and organization?",
                answer: "Currently, the app backs up photos organized by date. Album information is not preserved in the backup structure."
            )

            DocFAQItem(
                question: "Can I use this with iCloud Shared Photo Library?",
                answer: "The app backs up photos from your personal iCloud Photos library. Shared library support depends on your Photos app configuration."
            )

            DocFAQItem(
                question: "How often should I verify my backups?",
                answer: "We recommend running a quick verification after each backup, and a full verification monthly to ensure complete backup integrity."
            )
        }
    }
}

// MARK: - Documentation Helper Views

struct DocHeading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.top, 8)
    }
}

struct DocSubheading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3)
            .fontWeight(.medium)
            .padding(.top, 4)
    }
}

struct DocParagraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
    }
}

struct DocBulletList: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(item))
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }
}

struct DocNumberedList: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(LocalizedStringKey(item))
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }
}

struct DocDefinitionList: View {
    let items: [(String, String)]

    init(_ items: [(String, String)]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { term, definition in
                VStack(alignment: .leading, spacing: 4) {
                    Text(term)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(definition)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 8)
    }
}

struct DocTip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            Text(text)
                .font(.body)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DocWarning: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            Text(text)
                .font(.body)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DocFAQItem: View {
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("Q:")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text(question)
                    .font(.headline)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("A:")
                    .font(.body)
                    .foregroundStyle(.green)
                Text(answer)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    DocumentationView()
        .frame(width: 1000, height: 800)
}
