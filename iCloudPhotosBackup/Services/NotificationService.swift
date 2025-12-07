import Foundation
import UserNotifications
import OSLog

/// Service for sending macOS notifications for backup and verification job status
class NotificationService: NSObject {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "Notifications")
    private let notificationCenter = UNUserNotificationCenter.current()

    // Notification categories
    private static let backupCategory = "BACKUP_CATEGORY"
    private static let verificationCategory = "VERIFICATION_CATEGORY"
    private static let scheduledCategory = "SCHEDULED_CATEGORY"

    // User defaults key for notification preference
    private static let notificationsEnabledKey = "notificationsEnabled"

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.notificationsEnabledKey) }
    }

    private override init() {
        super.init()
        // Set default to true if not previously set
        if UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.notificationsEnabledKey)
        }
    }

    // MARK: - Authorization

    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("Notification authorization granted")
                await setupCategories()
            } else {
                logger.info("Notification authorization denied")
            }
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    /// Setup notification categories and actions
    private func setupCategories() async {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: .foreground
        )

        let backupCategory = UNNotificationCategory(
            identifier: Self.backupCategory,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let verificationCategory = UNNotificationCategory(
            identifier: Self.verificationCategory,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let scheduledCategory = UNNotificationCategory(
            identifier: Self.scheduledCategory,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            backupCategory,
            verificationCategory,
            scheduledCategory
        ])
    }

    // MARK: - Backup Notifications

    /// Send notification when a backup job starts
    func notifyBackupStarted(destinationName: String, photoCount: Int) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Backup Started"
        content.body = "Backing up \(photoCount) photos to \(destinationName)"
        content.sound = .default
        content.categoryIdentifier = Self.backupCategory

        sendNotification(identifier: "backup-started-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a backup job completes successfully
    func notifyBackupCompleted(
        destinationName: String,
        photosUploaded: Int,
        photosFailed: Int,
        duration: TimeInterval
    ) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.backupCategory

        let durationString = formatDuration(duration)

        if photosFailed == 0 {
            content.title = "Backup Complete"
            content.body = "Successfully backed up \(photosUploaded) photos to \(destinationName) in \(durationString)"
            content.sound = .default
        } else {
            content.title = "Backup Completed with Errors"
            content.body = "Backed up \(photosUploaded) photos, \(photosFailed) failed to \(destinationName)"
            content.sound = UNNotificationSound.defaultCritical
        }

        sendNotification(identifier: "backup-completed-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a backup job fails
    func notifyBackupFailed(destinationName: String, error: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Backup Failed"
        content.body = "Backup to \(destinationName) failed: \(error)"
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = Self.backupCategory

        sendNotification(identifier: "backup-failed-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a backup job is paused
    func notifyBackupPaused(destinationName: String, progress: Int) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Backup Paused"
        content.body = "Backup to \(destinationName) paused at \(progress)%"
        content.sound = .default
        content.categoryIdentifier = Self.backupCategory

        sendNotification(identifier: "backup-paused-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a backup job is cancelled
    func notifyBackupCancelled(destinationName: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Backup Cancelled"
        content.body = "Backup to \(destinationName) was cancelled"
        content.sound = .default
        content.categoryIdentifier = Self.backupCategory

        sendNotification(identifier: "backup-cancelled-\(UUID().uuidString)", content: content)
    }

    // MARK: - Verification Notifications

    /// Send notification when a verification job starts
    func notifyVerificationStarted(destinationName: String, type: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Verification Started"
        content.body = "\(type) verification started for \(destinationName)"
        content.sound = .default
        content.categoryIdentifier = Self.verificationCategory

        sendNotification(identifier: "verification-started-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a verification job completes
    func notifyVerificationCompleted(
        destinationName: String,
        verified: Int,
        missing: Int,
        mismatched: Int,
        errors: Int
    ) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.verificationCategory

        let hasIssues = missing > 0 || mismatched > 0 || errors > 0

        if hasIssues {
            content.title = "Verification Complete - Issues Found"
            var issues: [String] = []
            if missing > 0 { issues.append("\(missing) missing") }
            if mismatched > 0 { issues.append("\(mismatched) mismatched") }
            if errors > 0 { issues.append("\(errors) errors") }
            content.body = "Verified \(verified) photos. Issues: \(issues.joined(separator: ", "))"
            content.sound = UNNotificationSound.defaultCritical
        } else {
            content.title = "Verification Complete"
            content.body = "All \(verified) photos verified successfully for \(destinationName)"
            content.sound = .default
        }

        sendNotification(identifier: "verification-completed-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a verification job fails
    func notifyVerificationFailed(destinationName: String, error: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Verification Failed"
        content.body = "Verification for \(destinationName) failed: \(error)"
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = Self.verificationCategory

        sendNotification(identifier: "verification-failed-\(UUID().uuidString)", content: content)
    }

    // MARK: - Scheduled Job Notifications

    /// Send notification when a scheduled job starts
    func notifyScheduledJobStarted(jobName: String, destinationName: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Scheduled Backup Started"
        content.body = "Running scheduled backup '\(jobName)' to \(destinationName)"
        content.sound = .default
        content.categoryIdentifier = Self.scheduledCategory

        sendNotification(identifier: "scheduled-started-\(UUID().uuidString)", content: content)
    }

    /// Send notification when a scheduled job completes
    func notifyScheduledJobCompleted(
        jobName: String,
        destinationName: String,
        photosUploaded: Int,
        success: Bool
    ) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.scheduledCategory

        if success {
            content.title = "Scheduled Backup Complete"
            content.body = "'\(jobName)' backed up \(photosUploaded) photos to \(destinationName)"
            content.sound = .default
        } else {
            content.title = "Scheduled Backup Failed"
            content.body = "'\(jobName)' to \(destinationName) encountered errors"
            content.sound = UNNotificationSound.defaultCritical
        }

        sendNotification(identifier: "scheduled-completed-\(UUID().uuidString)", content: content)
    }

    // MARK: - Gap Detection Notifications

    /// Send notification when gap detection completes
    func notifyGapDetectionCompleted(destinationName: String, gapsFound: Int) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.verificationCategory

        if gapsFound > 0 {
            content.title = "Gap Detection Complete"
            content.body = "Found \(gapsFound) photos not backed up to \(destinationName)"
            content.sound = UNNotificationSound.defaultCritical
        } else {
            content.title = "Gap Detection Complete"
            content.body = "All photos are backed up to \(destinationName)"
            content.sound = .default
        }

        sendNotification(identifier: "gap-detection-\(UUID().uuidString)", content: content)
    }

    // MARK: - Private Helpers

    private func sendNotification(identifier: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send notification: \(error.localizedDescription)")
            } else {
                self?.logger.debug("Notification sent: \(identifier)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }
}
