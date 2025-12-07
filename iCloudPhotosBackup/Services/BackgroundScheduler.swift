import Foundation
import OSLog

/// Manages background sync scheduling using NSBackgroundActivityScheduler
class BackgroundScheduler {
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "Scheduler")
    private var scheduler: NSBackgroundActivityScheduler?
    private var scheduledJobsTimer: Timer?
    private let appState: AppState

    // Configuration
    private(set) var isEnabled = false
    private(set) var interval: TimeInterval = 24 * 60 * 60 // 24 hours default
    private(set) var requiresCharging = true
    private(set) var preferredTimeWindow: (start: Int, end: Int) = (2, 6) // 2 AM - 6 AM

    // MARK: - Initialization

    init(appState: AppState) {
        self.appState = appState
        loadConfiguration()
        startScheduledJobsMonitor()
        logger.info("BackgroundScheduler initialized")
    }

    // MARK: - Schedule Management

    func enable() {
        guard !isEnabled else {
            logger.warning("Scheduler already enabled")
            return
        }

        logger.info("Enabling background scheduler")
        isEnabled = true
        saveConfiguration()
        setupScheduler()
    }

    func disable() {
        guard isEnabled else {
            logger.warning("Scheduler already disabled")
            return
        }

        logger.info("Disabling background scheduler")
        isEnabled = false
        saveConfiguration()
        teardownScheduler()
    }

    func updateInterval(_ newInterval: TimeInterval) {
        logger.info("Updating schedule interval to \(newInterval) seconds")
        interval = newInterval
        saveConfiguration()

        if isEnabled {
            setupScheduler()
        }
    }

    func updateRequiresCharging(_ requires: Bool) {
        logger.info("Updating requires charging: \(requires)")
        requiresCharging = requires
        saveConfiguration()

        if isEnabled {
            setupScheduler()
        }
    }

    func updatePreferredTimeWindow(start: Int, end: Int) {
        logger.info("Updating preferred time window: \(start):00 - \(end):00")
        preferredTimeWindow = (start, end)
        saveConfiguration()

        if isEnabled {
            setupScheduler()
        }
    }

    // MARK: - Scheduler Setup

    private func setupScheduler() {
        // Tear down existing scheduler
        teardownScheduler()

        // Create new scheduler
        let identifier = "com.icloudphotosbackup.sync"
        scheduler = NSBackgroundActivityScheduler(identifier: identifier)

        guard let scheduler = scheduler else {
            logger.error("Failed to create background activity scheduler")
            return
        }

        // Configure scheduler
        scheduler.interval = interval
        scheduler.repeats = true
        scheduler.qualityOfService = .utility

        // Set requirements
        if requiresCharging {
            // Only run when plugged in
            scheduler.tolerance = interval * 0.25 // Allow 25% flexibility
        } else {
            scheduler.tolerance = interval * 0.1 // Less flexibility when not requiring power
        }

        // Schedule the activity
        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }

            self.logger.info("Background sync triggered")

            Task {
                await self.performBackgroundSync()
                completion(.finished)
            }
        }

        logger.info("Background scheduler configured with interval: \(self.interval)s")
    }

    private func teardownScheduler() {
        if let scheduler = scheduler {
            scheduler.invalidate()
            self.scheduler = nil
            logger.info("Background scheduler invalidated")
        }
    }

    // MARK: - Background Sync Execution

    private func performBackgroundSync() async {
        logger.info("Starting background sync execution")

        // Check if we're in the preferred time window
        if !isInPreferredTimeWindow() {
            logger.info("Outside preferred time window, skipping sync")
            return
        }

        // Check system resources
        guard await checkSystemResources() else {
            logger.info("System resources not suitable for background sync")
            return
        }

        // Check if a sync is already running
        if appState.syncEngine.state == .syncing || appState.syncEngine.state == .preparing {
            logger.warning("Sync already in progress, skipping background sync")
            return
        }

        // Get destinations to sync
        await appState.loadDestinations()

        guard !appState.destinations.isEmpty else {
            logger.info("No destinations configured, skipping background sync")
            return
        }

        // Sync each destination
        for destination in appState.destinations {
            // Check if we should still continue
            guard await checkSystemResources() else {
                logger.info("System resources depleted, stopping background sync")
                break
            }

            logger.info("Background syncing destination: \(destination.name)")

            do {
                // Use incremental sync (only new photos)
                try await appState.startSync(
                    destinationID: destination.id,
                    filter: .fullLibrary
                )

                logger.info("Background sync completed for: \(destination.name)")

            } catch {
                logger.error("Background sync failed for \(destination.name): \(error.localizedDescription)")
                // Continue with next destination
            }
        }

        logger.info("Background sync execution completed")
    }

    // MARK: - System Checks

    private func isInPreferredTimeWindow() -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        let (start, end) = preferredTimeWindow

        // Handle window crossing midnight
        if start < end {
            return hour >= start && hour < end
        } else {
            return hour >= start || hour < end
        }
    }

    private func checkSystemResources() async -> Bool {
        // Check thermal state
        let thermalState = ProcessInfo.processInfo.thermalState
        guard thermalState == .nominal || thermalState == .fair else {
            logger.warning("Thermal state not suitable: \(String(describing: thermalState))")
            return false
        }

        // Check if on battery power (if required)
        if requiresCharging {
            let powerSource = getPowerSource()
            guard powerSource == .AC else {
                logger.info("Not on AC power, skipping (requires charging)")
                return false
            }
        }

        // Check available disk space
        guard hasAvailableDiskSpace() else {
            logger.warning("Insufficient disk space")
            return false
        }

        return true
    }

    private func getPowerSource() -> PowerSource {
        // Check if running on AC power
        // This is a simplified check - real implementation would use IOKit
        let processInfo = ProcessInfo.processInfo

        // On macOS, we can check if low power mode is enabled
        // If low power mode is enabled, likely on battery
        if processInfo.isLowPowerModeEnabled {
            return .battery
        }

        return .AC
    }

    private func hasAvailableDiskSpace() -> Bool {
        do {
            let fileManager = FileManager.default
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())

            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                let freeBytes = freeSpace.int64Value
                let minimumRequired: Int64 = 1024 * 1024 * 1024 // 1 GB

                return freeBytes > minimumRequired
            }
        } catch {
            logger.error("Failed to check disk space: \(error.localizedDescription)")
        }

        return true // Assume OK if we can't check
    }

    // MARK: - Configuration Persistence

    private func loadConfiguration() {
        let defaults = UserDefaults.standard

        isEnabled = defaults.bool(forKey: "scheduler.enabled")

        if let savedInterval = defaults.object(forKey: "scheduler.interval") as? TimeInterval {
            interval = savedInterval
        }

        requiresCharging = defaults.object(forKey: "scheduler.requiresCharging") as? Bool ?? true

        if let start = defaults.object(forKey: "scheduler.timeWindow.start") as? Int,
           let end = defaults.object(forKey: "scheduler.timeWindow.end") as? Int {
            preferredTimeWindow = (start, end)
        }

        logger.info("Loaded scheduler configuration: enabled=\(self.isEnabled), interval=\(self.interval)")
    }

    private func saveConfiguration() {
        let defaults = UserDefaults.standard

        defaults.set(isEnabled, forKey: "scheduler.enabled")
        defaults.set(interval, forKey: "scheduler.interval")
        defaults.set(requiresCharging, forKey: "scheduler.requiresCharging")
        defaults.set(preferredTimeWindow.start, forKey: "scheduler.timeWindow.start")
        defaults.set(preferredTimeWindow.end, forKey: "scheduler.timeWindow.end")

        logger.debug("Saved scheduler configuration")
    }

    // MARK: - Manual Trigger

    func triggerManualSync() async {
        logger.info("Manual background sync triggered")
        await performBackgroundSync()
    }

    // MARK: - Scheduled Jobs Monitor

    private func startScheduledJobsMonitor() {
        // Check for due jobs every minute
        scheduledJobsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAndRunDueJobs()
            }
        }
        logger.info("Scheduled jobs monitor started")

        // Also check immediately on startup
        Task {
            await checkAndRunDueJobs()
        }
    }

    func stopScheduledJobsMonitor() {
        scheduledJobsTimer?.invalidate()
        scheduledJobsTimer = nil
        logger.info("Scheduled jobs monitor stopped")
    }

    private func checkAndRunDueJobs() async {
        do {
            let dueJobs = try appState.database.getJobsDueForExecution()

            for job in dueJobs {
                logger.info("Found due job: \(job.name)")
                await runScheduledJob(job)
            }
        } catch {
            logger.error("Failed to check for due jobs: \(error.localizedDescription)")
        }
    }

    @MainActor
    func runScheduledJob(_ job: ScheduledBackupJob) async {
        logger.info("Running scheduled job: \(job.name)")

        // Check system resources
        guard await checkSystemResources() else {
            logger.info("System resources not suitable, skipping job: \(job.name)")
            return
        }

        // Check if a sync is already running
        if appState.syncEngine.state == .syncing || appState.syncEngine.state == .preparing {
            logger.warning("Sync already in progress, skipping scheduled job: \(job.name)")
            return
        }

        let startTime = Date()
        var status: SyncJob.SyncJobStatus = .completed

        do {
            // Start the sync
            try await appState.startSync(
                destinationID: job.destinationID,
                filter: job.filter.toDateRangeFilter
            )

            logger.info("Scheduled job completed: \(job.name)")

        } catch {
            logger.error("Scheduled job failed: \(job.name) - \(error.localizedDescription)")
            status = .failed
        }

        // Calculate next run time
        var updatedJob = job
        updatedJob.lastRunTime = startTime
        updatedJob.nextRunTime = updatedJob.calculateNextRunTime()
        updatedJob.lastRunStatus = status

        // Update the job in database
        do {
            try appState.database.updateScheduledJobAfterRun(
                id: job.id,
                lastRunTime: startTime,
                nextRunTime: updatedJob.nextRunTime,
                status: status
            )

            // Reload scheduled jobs in app state
            await appState.loadScheduledJobs()

            // If it was a one-time job and it's done, disable it
            if case .oneTime = job.scheduleType {
                try appState.database.toggleScheduledBackupJob(id: job.id, isEnabled: false)
                await appState.loadScheduledJobs()
            }
        } catch {
            logger.error("Failed to update job after run: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

enum PowerSource {
    case AC
    case battery
    case unknown
}

// MARK: - Schedule Presets

extension BackgroundScheduler {
    static let presets: [(name: String, interval: TimeInterval)] = [
        ("Every 6 hours", 6 * 60 * 60),
        ("Every 12 hours", 12 * 60 * 60),
        ("Daily", 24 * 60 * 60),
        ("Every 2 days", 2 * 24 * 60 * 60),
        ("Weekly", 7 * 24 * 60 * 60)
    ]
}
