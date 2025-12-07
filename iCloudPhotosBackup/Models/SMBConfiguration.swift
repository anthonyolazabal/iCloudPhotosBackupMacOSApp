import Foundation

/// Configuration for SMB (Server Message Block) network share destinations
struct SMBConfiguration: DestinationConfiguration, Codable {
    let id: UUID
    var name: String
    let type: DestinationType = .smb
    let createdAt: Date

    // MARK: - Server Settings

    /// Server hostname or IP address (e.g., "192.168.1.100" or "nas.local")
    var serverAddress: String

    /// Share name on the server (e.g., "Photos", "Backups")
    var shareName: String

    /// SMB port (default: 445)
    var port: Int

    /// Optional subfolder path within the share
    var pathPrefix: String

    // MARK: - Authentication

    /// Authentication type
    var authType: SMBAuthType

    /// Username for authentication (empty for guest)
    var username: String

    /// Password for authentication (empty for guest)
    var password: String

    /// Optional workgroup or domain name
    var domain: String

    // MARK: - Types

    enum SMBAuthType: String, Codable, CaseIterable {
        case guest = "guest"
        case credentials = "credentials"

        var displayName: String {
            switch self {
            case .guest: return "Guest (No Authentication)"
            case .credentials: return "Username & Password"
            }
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, name, type, createdAt
        case serverAddress, shareName, port, pathPrefix
        case authType, username, password, domain
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        serverAddress: String,
        shareName: String,
        port: Int = 445,
        pathPrefix: String = "",
        authType: SMBAuthType = .credentials,
        username: String = "",
        password: String = "",
        domain: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.shareName = shareName
        self.port = port
        self.pathPrefix = pathPrefix
        self.authType = authType
        self.username = username
        self.password = password
        self.domain = domain
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// Builds the SMB URL for mounting
    /// Format: smb://[domain;]user:password@server:port/share
    var smbURL: URL? {
        var urlString = "smb://"

        if authType == .credentials && !username.isEmpty {
            // Add domain if present
            if !domain.isEmpty {
                urlString += "\(domain);"
            }

            // Add username
            let escapedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            urlString += escapedUsername

            // Add password if present
            if !password.isEmpty {
                let escapedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                urlString += ":\(escapedPassword)"
            }

            urlString += "@"
        }

        // Add server address
        urlString += serverAddress

        // Add port if non-standard
        if port != 445 {
            urlString += ":\(port)"
        }

        // Add share name
        let escapedShare = shareName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareName
        urlString += "/\(escapedShare)"

        return URL(string: urlString)
    }

    /// URL without credentials (for display purposes)
    var displayURL: String {
        var urlString = "smb://\(serverAddress)"
        if port != 445 {
            urlString += ":\(port)"
        }
        urlString += "/\(shareName)"
        return urlString
    }

    // MARK: - Validation

    func validate() throws {
        guard !name.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Name")
        }

        guard !serverAddress.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Server Address")
        }

        // Validate server address format (IP or hostname)
        if !isValidServerAddress(serverAddress) {
            throw ValidationError.invalidFormat(
                fieldName: "Server Address",
                expectedFormat: "IP address or hostname (e.g., 192.168.1.100 or nas.local)"
            )
        }

        guard !shareName.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Share Name")
        }

        // Validate share name (no slashes or special chars)
        if shareName.contains("/") || shareName.contains("\\") {
            throw ValidationError.invalidFormat(
                fieldName: "Share Name",
                expectedFormat: "Share name without slashes"
            )
        }

        guard port > 0 && port <= 65535 else {
            throw ValidationError.invalidFormat(
                fieldName: "Port",
                expectedFormat: "Valid port number (1-65535)"
            )
        }

        // Validate credentials if using authentication
        if authType == .credentials {
            guard !username.isEmpty else {
                throw ValidationError.emptyField(fieldName: "Username")
            }
        }

        // Validate path prefix if provided
        if !pathPrefix.isEmpty {
            // Remove leading/trailing slashes for consistency
            let cleanPath = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            if cleanPath.contains("..") {
                throw ValidationError.invalidFormat(
                    fieldName: "Path Prefix",
                    expectedFormat: "Valid folder path without '..' references"
                )
            }
        }
    }

    private func isValidServerAddress(_ address: String) -> Bool {
        // Check if it's a valid IPv4 address
        let ipv4Pattern = #"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        if address.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }

        // Check if it's a valid hostname
        let hostnamePattern = #"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"#
        if address.range(of: hostnamePattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    // MARK: - Normalized Path Prefix

    /// Returns the path prefix with consistent formatting (no leading slash, trailing slash)
    var normalizedPathPrefix: String {
        var path = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if !path.isEmpty {
            path += "/"
        }
        return path
    }
}

// MARK: - Preset Configurations

extension SMBConfiguration {
    /// Create a configuration for a local network share
    static func localShare(
        name: String,
        serverAddress: String,
        shareName: String,
        username: String,
        password: String,
        pathPrefix: String = ""
    ) -> SMBConfiguration {
        SMBConfiguration(
            name: name,
            serverAddress: serverAddress,
            shareName: shareName,
            pathPrefix: pathPrefix,
            authType: .credentials,
            username: username,
            password: password
        )
    }

    /// Create a guest access configuration
    static func guestShare(
        name: String,
        serverAddress: String,
        shareName: String,
        pathPrefix: String = ""
    ) -> SMBConfiguration {
        SMBConfiguration(
            name: name,
            serverAddress: serverAddress,
            shareName: shareName,
            pathPrefix: pathPrefix,
            authType: .guest
        )
    }
}
