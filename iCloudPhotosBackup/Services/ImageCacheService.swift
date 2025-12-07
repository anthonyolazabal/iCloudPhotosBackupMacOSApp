import Foundation
import AppKit
import OSLog
import CryptoKit

/// Service for caching downloaded images from remote storage
/// Provides both in-memory and disk caching for thumbnails and full images
actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "ImageCache")

    // Configuration
    private let maxMemoryCacheCount = 100
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB

    // MARK: - Initialization

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("iCloudPhotosBackup/thumbnails", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        memoryCache.countLimit = maxMemoryCacheCount
        memoryCache.name = "com.icloudphotosbackup.imagecache"

        logger.info("ImageCacheService initialized at: \(self.cacheDirectory.path)")
    }

    // MARK: - Thumbnail Cache

    /// Get a cached thumbnail for a remote path
    /// - Parameters:
    ///   - path: Remote file path
    ///   - size: Desired thumbnail size
    /// - Returns: Cached image or nil if not found
    func getThumbnail(for path: String, size: CGSize) -> NSImage? {
        let cacheKey = thumbnailCacheKey(for: path, size: size)

        // Check memory cache first
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            logger.debug("Memory cache hit: \(path)")
            return cached
        }

        // Check disk cache
        let fileURL = diskCacheURL(for: cacheKey)
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            // Store in memory cache for faster access
            memoryCache.setObject(image, forKey: cacheKey as NSString)
            logger.debug("Disk cache hit: \(path)")
            return image
        }

        logger.debug("Cache miss: \(path)")
        return nil
    }

    /// Cache a thumbnail for a remote path
    /// - Parameters:
    ///   - image: Image to cache
    ///   - path: Remote file path
    ///   - size: Thumbnail size
    func cacheThumbnail(_ image: NSImage, for path: String, size: CGSize) {
        let cacheKey = thumbnailCacheKey(for: path, size: size)

        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey as NSString)

        // Store in disk cache
        let fileURL = diskCacheURL(for: cacheKey)
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? jpegData.write(to: fileURL)
            logger.debug("Cached thumbnail: \(path)")
        }
    }

    // MARK: - Full Image Cache

    /// Get a cached full image for a remote path
    /// - Parameter path: Remote file path
    /// - Returns: Cached image or nil if not found
    func getFullImage(for path: String) -> NSImage? {
        let cacheKey = fullImageCacheKey(for: path)

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache
        let fileURL = diskCacheURL(for: cacheKey)
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey as NSString)
            return image
        }

        return nil
    }

    /// Cache a full image for a remote path
    /// - Parameters:
    ///   - image: Image to cache
    ///   - path: Remote file path
    func cacheFullImage(_ image: NSImage, for path: String) {
        let cacheKey = fullImageCacheKey(for: path)

        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey as NSString)

        // Store in disk cache (use original format for quality)
        let fileURL = diskCacheURL(for: cacheKey)
        if let tiffData = image.tiffRepresentation {
            try? tiffData.write(to: fileURL)
        }
    }

    // MARK: - Cache Management

    /// Clear all cached images
    func clearCache() {
        // Clear memory cache
        memoryCache.removeAllObjects()

        // Clear disk cache
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        logger.info("Cache cleared")
    }

    /// Get the current disk cache size in bytes
    func getDiskCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    /// Get formatted disk cache size
    func getFormattedCacheSize() -> String {
        ByteCountFormatter.string(fromByteCount: getDiskCacheSize(), countStyle: .file)
    }

    /// Evict old cache entries if over size limit
    func evictIfNeeded() {
        let currentSize = getDiskCacheSize()

        guard currentSize > maxDiskCacheSize else { return }

        logger.info("Cache size \(currentSize) exceeds limit, evicting old entries")

        // Get all cached files with modification dates
        var cachedFiles: [(URL, Date)] = []

        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    cachedFiles.append((fileURL, modDate))
                }
            }
        }

        // Sort by modification date (oldest first)
        cachedFiles.sort { $0.1 < $1.1 }

        // Delete oldest files until under limit
        var deletedSize: Int64 = 0
        let targetDeletion = currentSize - (maxDiskCacheSize / 2) // Delete down to 50% of limit

        for (fileURL, _) in cachedFiles {
            guard deletedSize < targetDeletion else { break }

            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? fileManager.removeItem(at: fileURL)
                deletedSize += Int64(fileSize)
            }
        }

        logger.info("Evicted \(deletedSize) bytes from cache")
    }

    // MARK: - Helper Methods

    private func thumbnailCacheKey(for path: String, size: CGSize) -> String {
        let sizeString = "\(Int(size.width))x\(Int(size.height))"
        return "thumb_\(sizeString)_\(path.sha256Hash)"
    }

    private func fullImageCacheKey(for path: String) -> String {
        return "full_\(path.sha256Hash)"
    }

    private func diskCacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key + ".cache")
    }
}

// MARK: - String Extension for Hashing

extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Thumbnail Generator

extension NSImage {
    /// Create a thumbnail of the image with the specified maximum size
    /// - Parameter maxSize: Maximum width or height
    /// - Returns: Resized thumbnail image
    func thumbnail(maxSize: CGFloat) -> NSImage {
        let originalSize = self.size

        guard originalSize.width > 0 && originalSize.height > 0 else {
            return self
        }

        // Calculate aspect-fit size
        let widthRatio = maxSize / originalSize.width
        let heightRatio = maxSize / originalSize.height
        let ratio = min(widthRatio, heightRatio)

        // Don't upscale
        guard ratio < 1.0 else { return self }

        let newSize = NSSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        self.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()

        return newImage
    }
}
