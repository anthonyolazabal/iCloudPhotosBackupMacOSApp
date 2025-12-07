import Foundation

/// Settings for photo export behavior
struct ExportSettings: Codable {
    /// Whether to convert HEIC images to JPEG
    var convertHEICToJPEG: Bool = false

    /// JPEG quality when converting (0.0 to 1.0)
    var jpegQuality: Double = 0.9

    /// How to handle Live Photos
    var livePhotosMode: LivePhotosMode = .both

    /// Whether to obfuscate filenames for privacy
    var obfuscateFilenames: Bool = false

    /// Whether to preserve original file modification dates
    var preserveModificationDates: Bool = true

    /// Whether to encrypt files before upload
    var encryptFiles: Bool = false

    enum LivePhotosMode: String, Codable, CaseIterable {
        case both = "Export both photo and video"
        case photoOnly = "Export photo only"
        case videoOnly = "Export video only"

        var description: String {
            return self.rawValue
        }
    }

    // MARK: - Validation

    func validate() throws {
        if jpegQuality < 0.0 || jpegQuality > 1.0 {
            throw ValidationError.invalidFormat(
                fieldName: "JPEG Quality",
                expectedFormat: "Value between 0.0 and 1.0"
            )
        }
    }

    // MARK: - Defaults

    static let `default` = ExportSettings()

    static let highQuality = ExportSettings(
        convertHEICToJPEG: false,
        jpegQuality: 1.0,
        livePhotosMode: .both,
        obfuscateFilenames: false,
        preserveModificationDates: true
    )

    static let compatibility = ExportSettings(
        convertHEICToJPEG: true,
        jpegQuality: 0.9,
        livePhotosMode: .photoOnly,
        obfuscateFilenames: false,
        preserveModificationDates: true
    )

    static let privacy = ExportSettings(
        convertHEICToJPEG: false,
        jpegQuality: 0.9,
        livePhotosMode: .both,
        obfuscateFilenames: true,
        preserveModificationDates: false
    )
}
