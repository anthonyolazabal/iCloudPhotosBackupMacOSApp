import XCTest
@testable import iCloudPhotosBackup

final class ExtensionsTests: XCTestCase {

    // MARK: - Array Chunked Tests

    func testArrayChunkedEvenDivision() {
        let array = [1, 2, 3, 4, 5, 6]
        let chunks = array.chunked(into: 2)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2])
        XCTAssertEqual(chunks[1], [3, 4])
        XCTAssertEqual(chunks[2], [5, 6])
    }

    func testArrayChunkedUnevenDivision() {
        let array = [1, 2, 3, 4, 5, 6, 7]
        let chunks = array.chunked(into: 3)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7])
    }

    func testArrayChunkedLargerThanArray() {
        let array = [1, 2, 3]
        let chunks = array.chunked(into: 10)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], [1, 2, 3])
    }

    func testArrayChunkedSizeOne() {
        let array = [1, 2, 3]
        let chunks = array.chunked(into: 1)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1])
        XCTAssertEqual(chunks[1], [2])
        XCTAssertEqual(chunks[2], [3])
    }

    func testArrayChunkedEmptyArray() {
        let array: [Int] = []
        let chunks = array.chunked(into: 5)

        XCTAssertEqual(chunks.count, 0)
    }

    // MARK: - Collection Safe Subscript Tests

    func testSafeSubscriptValidIndex() {
        let array = ["a", "b", "c"]
        XCTAssertEqual(array[safe: 1], "b")
    }

    func testSafeSubscriptOutOfBounds() {
        let array = ["a", "b", "c"]
        XCTAssertNil(array[safe: 5])
        XCTAssertNil(array[safe: -1])
    }

    func testSafeSubscriptEmptyArray() {
        let array: [String] = []
        XCTAssertNil(array[safe: 0])
    }

    // MARK: - Data Hex String Tests

    func testDataToHexString() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello" in hex
        XCTAssertEqual(data.hexString, "48656c6c6f")
    }

    func testHexStringToData() {
        let hexString = "48656c6c6f"
        let data = Data(hexString: hexString)

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 5)
        XCTAssertEqual(data, Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]))
    }

    func testInvalidHexString() {
        let invalidHex = "xyz123"
        let data = Data(hexString: invalidHex)
        XCTAssertNil(data)
    }

    func testEmptyHexString() {
        let emptyHex = ""
        let data = Data(hexString: emptyHex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 0)
    }

    // MARK: - Date Extension Tests

    func testDateIsWithinDays() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!

        XCTAssertTrue(yesterday.isWithinDays(7))
        XCTAssertTrue(weekAgo.isWithinDays(7))
        XCTAssertFalse(monthAgo.isWithinDays(7))
    }

    // MARK: - String Extension Tests

    func testSanitizedFilename() {
        let unsafeFilename = "file/name:with*invalid\"chars"
        let safe = unsafeFilename.sanitizedFilename
        XCTAssertFalse(safe.contains("/"))
        XCTAssertFalse(safe.contains(":"))
        XCTAssertFalse(safe.contains("*"))
        XCTAssertFalse(safe.contains("\""))
    }

    func testTruncatedString() {
        let longString = "This is a very long string that needs to be truncated"

        let truncated = longString.truncated(to: 20)
        XCTAssertEqual(truncated.count, 20)
        XCTAssertTrue(truncated.hasSuffix("..."))

        let short = "Short"
        XCTAssertEqual(short.truncated(to: 20), "Short")
    }

    // MARK: - Int64 Extension Tests

    func testFormattedFileSize() {
        let bytes: Int64 = 1024
        XCTAssertTrue(bytes.formattedFileSize.contains("KB") || bytes.formattedFileSize.contains("kB"))

        let megabytes: Int64 = 1024 * 1024 * 5
        XCTAssertTrue(megabytes.formattedFileSize.contains("MB"))

        let gigabytes: Int64 = 1024 * 1024 * 1024 * 2
        XCTAssertTrue(gigabytes.formattedFileSize.contains("GB"))
    }

    // MARK: - TimeInterval Extension Tests

    func testFormattedDurationSeconds() {
        let seconds: TimeInterval = 45
        XCTAssertEqual(seconds.formattedDuration, "45s")
    }

    func testFormattedDurationMinutes() {
        let minutes: TimeInterval = 125 // 2m 5s
        XCTAssertEqual(minutes.formattedDuration, "2m 5s")
    }

    func testFormattedDurationHours() {
        let hours: TimeInterval = 3725 // 1h 2m 5s
        XCTAssertEqual(hours.formattedDuration, "1h 2m")
    }

    // MARK: - Optional String Tests

    func testIsNilOrEmptyNil() {
        let nilString: String? = nil
        XCTAssertTrue(nilString.isNilOrEmpty)
    }

    func testIsNilOrEmptyEmpty() {
        let emptyString: String? = ""
        XCTAssertTrue(emptyString.isNilOrEmpty)
    }

    func testIsNilOrEmptyNotEmpty() {
        let string: String? = "hello"
        XCTAssertFalse(string.isNilOrEmpty)
    }

    // MARK: - Result Extension Tests

    func testResultSuccessValue() {
        let success: Result<Int, Error> = .success(42)
        XCTAssertEqual(success.successValue, 42)
        XCTAssertNil(success.failureError)
    }

    func testResultFailureError() {
        enum TestError: Error { case test }
        let failure: Result<Int, TestError> = .failure(.test)
        XCTAssertNil(failure.successValue)
        XCTAssertNotNil(failure.failureError)
    }
}
