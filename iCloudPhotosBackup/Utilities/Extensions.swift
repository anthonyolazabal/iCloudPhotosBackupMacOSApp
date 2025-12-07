import Foundation

// MARK: - Array Extensions

extension Array {
    /// Splits the array into chunks of the specified size
    /// - Parameter size: Maximum size of each chunk
    /// - Returns: Array of arrays, each containing at most `size` elements
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Collection Extensions

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Data Extensions

extension Data {
    /// Returns hex string representation of the data
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }

    /// Initialize Data from a hex string
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)

        var index = hexString.startIndex
        for _ in 0..<length {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

// MARK: - Date Extensions

extension Date {
    /// Returns a human-readable relative time string
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Returns true if the date is within the last N days
    func isWithinDays(_ days: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let daysAgo = calendar.date(byAdding: .day, value: -days, to: now)!
        return self >= daysAgo
    }
}

// MARK: - String Extensions

extension String {
    /// Returns a sanitized filename (removes invalid characters)
    var sanitizedFilename: String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    /// Truncates the string to the specified length, adding ellipsis if needed
    func truncated(to length: Int, trailing: String = "...") -> String {
        if count <= length {
            return self
        }
        return String(prefix(length - trailing.count)) + trailing
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    /// Returns a human-readable file size string
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Returns a human-readable duration string
    var formattedDuration: String {
        let seconds = Int(self)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

// MARK: - URL Extensions

extension URL {
    /// Returns the file size in bytes, or nil if not available
    var fileSize: Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Returns true if the URL points to an existing file
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Returns true if the URL points to an existing directory
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    /// Returns true if the optional string is nil or empty
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}

// MARK: - Result Extensions

extension Result {
    /// Returns the success value or nil
    var successValue: Success? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }

    /// Returns the failure error or nil
    var failureError: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
