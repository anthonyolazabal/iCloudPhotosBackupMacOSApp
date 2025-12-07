import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// Handles image format conversion and metadata preservation
class ImageProcessor {
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "ImageProcessor")

    enum ConversionFormat: CustomStringConvertible {
        case jpeg(quality: CGFloat)
        case original

        var utType: UTType {
            switch self {
            case .jpeg:
                return .jpeg
            case .original:
                return .heic
            }
        }

        var description: String {
            switch self {
            case .jpeg(let quality):
                return "JPEG (quality: \(quality))"
            case .original:
                return "Original (HEIC)"
            }
        }
    }

    // MARK: - Convert Image

    /// Convert image to specified format while preserving metadata
    /// - Parameters:
    ///   - sourceURL: Source image file
    ///   - format: Target format
    ///   - destinationURL: Destination file URL
    /// - Returns: True if conversion successful
    func convertImage(from sourceURL: URL, to format: ConversionFormat, destinationURL: URL) throws {
        logger.info("Converting image from \(sourceURL.lastPathComponent) to \(format)")

        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            logger.error("Failed to create image source from: \(sourceURL.path)")
            throw NSError(domain: "ImageProcessor", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read source image"
            ])
        }

        // Read original metadata
        let metadata = copyMetadata(from: imageSource)

        // Create destination
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            logger.error("Failed to create image destination at: \(destinationURL.path)")
            throw NSError(domain: "ImageProcessor", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create destination image"
            ])
        }

        // Get the image
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            logger.error("Failed to get image from source")
            throw NSError(domain: "ImageProcessor", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode source image"
            ])
        }

        // Prepare options
        var options: [CFString: Any] = [:]

        // Add metadata
        if let metadata = metadata {
            options[kCGImageDestinationMetadata] = metadata
        }

        // Add compression quality for JPEG
        if case .jpeg(let quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        // Add the image with metadata
        CGImageDestinationAddImage(imageDestination, cgImage, options as CFDictionary)

        // Finalize
        guard CGImageDestinationFinalize(imageDestination) else {
            logger.error("Failed to finalize image destination")
            throw NSError(domain: "ImageProcessor", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to write converted image"
            ])
        }

        logger.info("Successfully converted image to: \(destinationURL.lastPathComponent)")
    }

    // MARK: - Metadata Operations

    /// Copy all metadata from image source
    /// - Parameter imageSource: CGImageSource
    /// - Returns: Metadata dictionary
    private func copyMetadata(from imageSource: CGImageSource) -> CFDictionary? {
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            logger.warning("No metadata found in source image")
            return nil
        }

        return metadata as CFDictionary
    }

    /// Extract specific metadata fields for logging/debugging
    /// - Parameter imageURL: Image file URL
    /// - Returns: Dictionary of metadata
    func extractMetadata(from imageURL: URL) -> [String: Any]? {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            logger.warning("Failed to extract metadata from: \(imageURL.lastPathComponent)")
            return nil
        }

        var extractedMetadata: [String: Any] = [:]

        // EXIF data
        if let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            extractedMetadata["EXIF"] = exif
        }

        // TIFF data
        if let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            extractedMetadata["TIFF"] = tiff
        }

        // GPS data
        if let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            extractedMetadata["GPS"] = gps
        }

        // IPTC data
        if let iptc = metadata[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            extractedMetadata["IPTC"] = iptc
        }

        // Basic properties
        if let width = metadata[kCGImagePropertyPixelWidth as String] {
            extractedMetadata["width"] = width
        }
        if let height = metadata[kCGImagePropertyPixelHeight as String] {
            extractedMetadata["height"] = height
        }
        if let orientation = metadata[kCGImagePropertyOrientation as String] {
            extractedMetadata["orientation"] = orientation
        }

        return extractedMetadata
    }

    /// Verify metadata preservation after conversion
    /// - Parameters:
    ///   - originalURL: Original image URL
    ///   - convertedURL: Converted image URL
    /// - Returns: True if critical metadata is preserved
    func verifyMetadataPreservation(originalURL: URL, convertedURL: URL) -> Bool {
        guard let originalMetadata = extractMetadata(from: originalURL),
              let convertedMetadata = extractMetadata(from: convertedURL) else {
            logger.error("Failed to extract metadata for verification")
            return false
        }

        // Check critical metadata fields
        let criticalFields = ["GPS", "EXIF"]
        for field in criticalFields {
            let originalHasField = originalMetadata[field] != nil
            let convertedHasField = convertedMetadata[field] != nil

            if originalHasField && !convertedHasField {
                logger.warning("Critical metadata field '\(field)' was lost during conversion")
                return false
            }
        }

        logger.info("Metadata verification passed")
        return true
    }

    // MARK: - Live Photos Handling

    /// Extract components from Live Photo
    /// - Parameter asset: PHAsset representing a Live Photo
    /// - Returns: Tuple of (photo URL, video URL) if successful
    func extractLivePhotoComponents(photoURL: URL, videoURL: URL?) -> (photo: URL, video: URL?) {
        // Live Photos consist of a still image and a short video
        // The photo URL is already provided, we just need to validate the video
        if let video = videoURL {
            logger.info("Live Photo detected with video component")
            return (photoURL, video)
        } else {
            logger.info("Processing as still photo (no Live Photo video component)")
            return (photoURL, nil)
        }
    }

    // MARK: - Image Validation

    /// Validate that an image file is readable and not corrupted
    /// - Parameter url: Image file URL
    /// - Returns: True if valid
    func validateImage(at url: URL) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.error("Failed to create image source for validation: \(url.lastPathComponent)")
            return false
        }

        let imageCount = CGImageSourceGetCount(imageSource)
        if imageCount == 0 {
            logger.error("Image contains no data: \(url.lastPathComponent)")
            return false
        }

        guard CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else {
            logger.error("Failed to decode image: \(url.lastPathComponent)")
            return false
        }

        logger.debug("Image validation passed: \(url.lastPathComponent)")
        return true
    }

    // MARK: - File Size Estimation

    /// Estimate JPEG file size for a given HEIC image
    /// - Parameters:
    ///   - heicURL: Source HEIC file
    ///   - quality: JPEG quality (0.0 to 1.0)
    /// - Returns: Estimated size in bytes
    func estimateJPEGSize(for heicURL: URL, quality: CGFloat) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: heicURL.path),
              let originalSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Rough estimation: JPEG is typically 0.6-0.8x the size of HEIC at high quality
        // At lower quality, it can be much smaller
        let estimatedRatio = 0.6 + (quality * 0.2)
        return Int64(Double(originalSize) * estimatedRatio)
    }
}
