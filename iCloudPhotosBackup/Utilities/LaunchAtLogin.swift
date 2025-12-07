import Foundation
import ServiceManagement
import OSLog

/// Manages launch at login functionality
class LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "LaunchAtLogin")

    // MARK: - Check Status

    static var isEnabled: Bool {
        get {
            // Check if app is registered to launch at login
            // This uses the modern SMAppService API (macOS 13+)
            let service = SMAppService.mainApp
            return service.status == .enabled
        }
    }

    // MARK: - Enable/Disable

    static func enable() throws {
        logger.info("Enabling launch at login")

        let service = SMAppService.mainApp

        do {
            try service.register()
            logger.info("Launch at login enabled successfully")
        } catch {
            logger.error("Failed to enable launch at login: \(error.localizedDescription)")
            throw LaunchAtLoginError.registrationFailed(underlying: error)
        }
    }

    static func disable() throws {
        logger.info("Disabling launch at login")

        let service = SMAppService.mainApp

        do {
            try service.unregister()
            logger.info("Launch at login disabled successfully")
        } catch {
            logger.error("Failed to disable launch at login: \(error.localizedDescription)")
            throw LaunchAtLoginError.unregistrationFailed(underlying: error)
        }
    }

    // MARK: - Toggle

    static func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }
}

// MARK: - Errors

enum LaunchAtLoginError: LocalizedError {
    case registrationFailed(underlying: Error)
    case unregistrationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let error):
            return "Failed to enable launch at login: \(error.localizedDescription)"
        case .unregistrationFailed(let error):
            return "Failed to disable launch at login: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .registrationFailed:
            return "Check System Settings > General > Login Items to manually configure"
        case .unregistrationFailed:
            return "Check System Settings > General > Login Items to manually remove"
        }
    }
}
