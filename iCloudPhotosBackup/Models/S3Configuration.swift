import Foundation

/// Configuration for S3-compatible storage destinations
struct S3Configuration: DestinationConfiguration {
    let id: UUID
    var name: String
    let type: DestinationType = .s3
    let createdAt: Date

    // S3-specific settings
    var endpointURL: String
    var region: String
    var bucketName: String
    var accessKeyID: String
    var secretAccessKey: String
    var pathPrefix: String

    // Advanced settings
    var usePathStyleAccess: Bool
    var storageClass: StorageClass
    var serverSideEncryption: ServerSideEncryption
    var httpProxyURL: String?

    // Provider preset
    var provider: S3Provider

    enum S3Provider: String, Codable, CaseIterable {
        case aws = "Amazon S3"
        case minio = "Minio"
        case ovh = "OVH Object Storage"
        case backblaze = "Backblaze B2"
        case wasabi = "Wasabi"
        case custom = "Custom S3-Compatible"

        var requiresPathStyle: Bool {
            switch self {
            case .minio:
                return true
            default:
                // OVH and other providers work with virtual-hosted style
                return false
            }
        }

        var defaultRegion: String {
            switch self {
            case .aws:
                return "us-east-1"
            case .minio:
                return "us-east-1"
            case .ovh:
                return "gra"
            case .backblaze:
                return "us-west-002"
            case .wasabi:
                return "us-east-1"
            case .custom:
                return "us-east-1"
            }
        }
    }

    enum StorageClass: String, Codable, CaseIterable {
        case standard = "STANDARD"
        case standardIA = "STANDARD_IA"
        case intelligentTiering = "INTELLIGENT_TIERING"
        case oneZoneIA = "ONEZONE_IA"
        case glacier = "GLACIER"
        case glacierDeepArchive = "DEEP_ARCHIVE"

        var description: String {
            switch self {
            case .standard:
                return "Standard (frequent access)"
            case .standardIA:
                return "Standard-IA (infrequent access)"
            case .intelligentTiering:
                return "Intelligent-Tiering (automatic cost optimization)"
            case .oneZoneIA:
                return "One Zone-IA (single AZ, infrequent access)"
            case .glacier:
                return "Glacier (archival, retrieval time: minutes to hours)"
            case .glacierDeepArchive:
                return "Glacier Deep Archive (long-term archival, retrieval time: 12 hours)"
            }
        }

        var estimatedCostMultiplier: Double {
            switch self {
            case .standard:
                return 1.0
            case .standardIA:
                return 0.5
            case .intelligentTiering:
                return 0.7
            case .oneZoneIA:
                return 0.4
            case .glacier:
                return 0.15
            case .glacierDeepArchive:
                return 0.05
            }
        }
    }

    enum ServerSideEncryption: String, Codable, CaseIterable {
        case none = "None"
        case aes256 = "AES256"
        case awsKMS = "aws:kms"

        var description: String {
            switch self {
            case .none:
                return "No server-side encryption"
            case .aes256:
                return "SSE-S3 (AES-256)"
            case .awsKMS:
                return "SSE-KMS (AWS Key Management Service)"
            }
        }

        var headerValue: String? {
            switch self {
            case .none:
                return nil
            case .aes256:
                return "AES256"
            case .awsKMS:
                return "aws:kms"
            }
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        endpointURL: String,
        region: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String,
        pathPrefix: String = "",
        usePathStyleAccess: Bool = false,
        storageClass: StorageClass = .standard,
        serverSideEncryption: ServerSideEncryption = .none,
        httpProxyURL: String? = nil,
        provider: S3Provider = .custom,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.region = region
        self.bucketName = bucketName
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.pathPrefix = pathPrefix
        self.usePathStyleAccess = usePathStyleAccess
        self.storageClass = storageClass
        self.serverSideEncryption = serverSideEncryption
        self.httpProxyURL = httpProxyURL
        self.provider = provider
        self.createdAt = createdAt
    }

    // MARK: - Validation

    func validate() throws {
        // Name validation
        guard !name.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Name")
        }

        // Endpoint URL validation
        guard !endpointURL.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Endpoint URL")
        }

        // Validate URL format
        guard let url = URL(string: endpointURL), url.scheme != nil else {
            throw ValidationError.invalidURL(url: endpointURL)
        }

        // Region validation
        guard !region.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Region")
        }

        // Bucket name validation
        guard !bucketName.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Bucket Name")
        }

        // Bucket name format validation (AWS S3 rules)
        let bucketNamePattern = "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"
        let bucketRegex = try NSRegularExpression(pattern: bucketNamePattern)
        let bucketRange = NSRange(bucketName.startIndex..., in: bucketName)
        if bucketRegex.firstMatch(in: bucketName, range: bucketRange) == nil {
            throw ValidationError.invalidFormat(
                fieldName: "Bucket Name",
                expectedFormat: "3-63 characters, lowercase letters, numbers, dots, and hyphens"
            )
        }

        // Credentials validation
        guard !accessKeyID.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Access Key ID")
        }

        guard !secretAccessKey.isEmpty else {
            throw ValidationError.emptyField(fieldName: "Secret Access Key")
        }

        // Proxy URL validation (if provided)
        if let proxyURL = httpProxyURL, !proxyURL.isEmpty {
            guard URL(string: proxyURL) != nil else {
                throw ValidationError.invalidURL(url: proxyURL)
            }
        }
    }

    // MARK: - Preset Configurations

    static func awsPreset(
        name: String,
        region: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String
    ) -> S3Configuration {
        return S3Configuration(
            name: name,
            endpointURL: "https://s3.\(region).amazonaws.com",
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            usePathStyleAccess: false,
            provider: .aws
        )
    }

    static func minioPreset(
        name: String,
        endpointURL: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String
    ) -> S3Configuration {
        return S3Configuration(
            name: name,
            endpointURL: endpointURL,
            region: "us-east-1",
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            usePathStyleAccess: true,
            provider: .minio
        )
    }

    /// OVH Object Storage regions
    enum OVHRegion: String, CaseIterable {
        // Europe
        case gra = "gra"                    // Gravelines, France
        case rbx = "rbx"                    // Roubaix, France
        case sbg = "sbg"                    // Strasbourg, France
        case euWestPar = "eu-west-par"      // Paris, France (3-AZ)
        case euSouthMil = "eu-south-mil"    // Milan, Italy (3-AZ)
        case de = "de"                      // Frankfurt, Germany
        case uk = "uk"                      // London, UK
        case waw = "waw"                    // Warsaw, Poland
        // North America
        case bhs = "bhs"                    // Beauharnois, Canada
        case caEastTor = "ca-east-tor"      // Toronto, Canada
        // Asia-Pacific
        case sgp = "sgp"                    // Singapore
        case apSoutheastSyd = "ap-southeast-syd"  // Sydney, Australia
        case apSouthMum = "ap-south-mum"    // Mumbai, India

        var displayName: String {
            switch self {
            case .gra: return "Gravelines (France)"
            case .rbx: return "Roubaix (France)"
            case .sbg: return "Strasbourg (France)"
            case .euWestPar: return "Paris (France) - 3-AZ"
            case .euSouthMil: return "Milan (Italy) - 3-AZ"
            case .de: return "Frankfurt (Germany)"
            case .uk: return "London (UK)"
            case .waw: return "Warsaw (Poland)"
            case .bhs: return "Beauharnois (Canada)"
            case .caEastTor: return "Toronto (Canada)"
            case .sgp: return "Singapore"
            case .apSoutheastSyd: return "Sydney (Australia)"
            case .apSouthMum: return "Mumbai (India)"
            }
        }

        var endpointURL: String {
            return "https://s3.\(rawValue).io.cloud.ovh.net"
        }
    }

    static func ovhPreset(
        name: String,
        region: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String
    ) -> S3Configuration {
        // Use the new endpoint format: s3.<region>.io.cloud.ovh.net
        let endpointURL = "https://s3.\(region).io.cloud.ovh.net"
        return S3Configuration(
            name: name,
            endpointURL: endpointURL,
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            usePathStyleAccess: false,
            provider: .ovh
        )
    }

    static func backblazePreset(
        name: String,
        region: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String
    ) -> S3Configuration {
        return S3Configuration(
            name: name,
            endpointURL: "https://s3.\(region).backblazeb2.com",
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            usePathStyleAccess: false,
            provider: .backblaze
        )
    }

    static func wasabiPreset(
        name: String,
        region: String,
        bucketName: String,
        accessKeyID: String,
        secretAccessKey: String
    ) -> S3Configuration {
        return S3Configuration(
            name: name,
            endpointURL: "https://s3.\(region).wasabisys.com",
            region: region,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            usePathStyleAccess: false,
            provider: .wasabi
        )
    }
}

// MARK: - Codable

extension S3Configuration {
    enum CodingKeys: String, CodingKey {
        case id, name, type, createdAt
        case endpointURL, region, bucketName
        case accessKeyID, secretAccessKey, pathPrefix
        case usePathStyleAccess, storageClass, serverSideEncryption
        case httpProxyURL, provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        endpointURL = try container.decode(String.self, forKey: .endpointURL)
        region = try container.decode(String.self, forKey: .region)
        bucketName = try container.decode(String.self, forKey: .bucketName)
        accessKeyID = try container.decode(String.self, forKey: .accessKeyID)
        secretAccessKey = try container.decode(String.self, forKey: .secretAccessKey)
        pathPrefix = try container.decodeIfPresent(String.self, forKey: .pathPrefix) ?? ""

        usePathStyleAccess = try container.decodeIfPresent(Bool.self, forKey: .usePathStyleAccess) ?? false
        storageClass = try container.decodeIfPresent(StorageClass.self, forKey: .storageClass) ?? .standard
        serverSideEncryption = try container.decodeIfPresent(ServerSideEncryption.self, forKey: .serverSideEncryption) ?? .none
        httpProxyURL = try container.decodeIfPresent(String.self, forKey: .httpProxyURL)
        provider = try container.decodeIfPresent(S3Provider.self, forKey: .provider) ?? .custom
    }
}
