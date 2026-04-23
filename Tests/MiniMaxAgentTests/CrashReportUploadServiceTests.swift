import XCTest
@testable import MiniMaxAgent

/// Tests for CrashReportUploadService
final class CrashReportUploadServiceTests: XCTestCase {

    // MARK: - Payload Tests

    func testPayloadCodingRoundTrip() throws {
        let payload = CrashReportUploadService.CrashReportPayload(
            bundleIdentifier: "com.example.app",
            appVersion: "1.2.3",
            buildNumber: "456",
            osVersion: "macOS 14.0",
            reportFileName: "ExampleApp_2026-03-30.crash",
            crashDate: "2026-03-30T10:00:00Z",
            reportContent: "Exception Type: EXC_BAD_ACCESS"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CrashReportUploadService.CrashReportPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testPayloadContainsAllFields() throws {
        let payload = CrashReportUploadService.CrashReportPayload(
            bundleIdentifier: "com.test",
            appVersion: "2.0",
            buildNumber: "100",
            osVersion: "macOS 15.0",
            reportFileName: "App_crash.crash",
            crashDate: "2026-01-01T00:00:00Z",
            reportContent: "Stack trace here"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["bundleIdentifier"])
        XCTAssertNotNil(json?["appVersion"])
        XCTAssertNotNil(json?["buildNumber"])
        XCTAssertNotNil(json?["osVersion"])
        XCTAssertNotNil(json?["reportFileName"])
        XCTAssertNotNil(json?["crashDate"])
        XCTAssertNotNil(json?["reportContent"])
    }

    // MARK: - UploadResult Tests

    func testUploadResultUploadedEquality() {
        let r1 = CrashReportUploadService.UploadResult.uploaded(fileName: "a.crash")
        let r2 = CrashReportUploadService.UploadResult.uploaded(fileName: "a.crash")
        XCTAssertEqual(r1, r2)
    }

    func testUploadResultSkippedAlreadyUploaded() {
        let r = CrashReportUploadService.UploadResult.skipped(fileName: "b.crash", reason: .alreadyUploaded)
        if case .skipped(let name, let reason) = r {
            XCTAssertEqual(name, "b.crash")
            XCTAssertEqual(reason, .alreadyUploaded)
        } else {
            XCTFail("Expected .skipped")
        }
    }

    func testUploadResultSkippedTooOld() {
        let r = CrashReportUploadService.UploadResult.skipped(fileName: "c.crash", reason: .tooOld)
        if case .skipped(_, let reason) = r {
            XCTAssertEqual(reason, .tooOld)
        } else {
            XCTFail("Expected .skipped")
        }
    }

    func testUploadResultSkippedReadError() {
        let r = CrashReportUploadService.UploadResult.skipped(fileName: "d.crash", reason: .readError)
        if case .skipped(_, let reason) = r {
            XCTAssertEqual(reason, .readError)
        } else {
            XCTFail("Expected .skipped")
        }
    }

    func testUploadResultFailedContainsError() {
        let r = CrashReportUploadService.UploadResult.failed(fileName: "e.crash", error: "Network error")
        if case .failed(let name, let error) = r {
            XCTAssertEqual(name, "e.crash")
            XCTAssertEqual(error, "Network error")
        } else {
            XCTFail("Expected .failed")
        }
    }

    // MARK: - Error Tests

    func testUploadErrorEncodingFailed() {
        let error = CrashReportUploadService.UploadError.encodingFailed("bad data")
        XCTAssertEqual(error.errorDescription, "Failed to encode crash report payload: bad data")
    }

    func testUploadErrorServerError() {
        let error = CrashReportUploadService.UploadError.serverError(500, "Internal Server Error")
        XCTAssertEqual(error.errorDescription, "Server returned 500: Internal Server Error")
    }

    // MARK: - Config Tests

    func testConfigDefaults() {
        let url = URL(string: "https://example.com/crashes")!
        let config = CrashReportUploadService.Config(endpointURL: url)
        XCTAssertEqual(config.endpointURL, url)
        XCTAssertEqual(config.maxReportsPerBatch, 10)
        XCTAssertEqual(config.maxReportAge, 7 * 24 * 3600)
    }

    func testConfigCustomValues() {
        let url = URL(string: "https://example.com/crashes")!
        let config = CrashReportUploadService.Config(
            endpointURL: url,
            maxReportsPerBatch: 5,
            maxReportAge: 3600
        )
        XCTAssertEqual(config.maxReportsPerBatch, 5)
        XCTAssertEqual(config.maxReportAge, 3600)
    }

    // MARK: - Service Initialization

    func testServiceInitialization() {
        let url = URL(string: "https://example.com/crashes")!
        let config = CrashReportUploadService.Config(endpointURL: url)
        let service = CrashReportUploadService(config: config)
        XCTAssertNotNil(service)
    }

    func testUploadPendingReportsWithBatchLimitZero() async {
        // With batch limit 0, no reports are processed — returns empty without crashing.
        let url = URL(string: "https://127.0.0.1:19999/crashes")!
        let config = CrashReportUploadService.Config(endpointURL: url, maxReportsPerBatch: 0)
        let service = CrashReportUploadService(config: config)
        let results = await service.uploadPendingReports()
        XCTAssertEqual(results.count, 0)
    }
}
