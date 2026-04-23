import XCTest
import CrashReporter
@testable import MiniMaxAgent

// MARK: - Fake PLCrashReporter

/// Minimal PLCrashReporter subclass used only for unit-testing the service.
final class FakePLCrashReporter: PLCrashReporter {

    var enableCalled = false
    var hasPending = false
    var pendingData: Data?
    var purgeCalled = false
    var enableShouldThrow = false

    override func enableAndReturnError() throws {
        if enableShouldThrow {
            throw NSError(domain: "FakePLCrashReporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Simulated enable failure"])
        }
        enableCalled = true
    }

    override func hasPendingCrashReport() -> Bool {
        return hasPending
    }

    override func loadPendingCrashReportDataAndReturnError() throws -> Data {
        guard let data = pendingData else {
            throw NSError(domain: "FakePLCrashReporter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No pending data"])
        }
        return data
    }

    override func purgePendingCrashReport() {
        purgeCalled = true
        hasPending = false
    }
}

// MARK: - CrashReporterServiceTests

final class CrashReporterServiceTests: XCTestCase {

    func testStartEnablesReporter() {
        let fake = FakePLCrashReporter()
        let service = CrashReporterService(reporter: fake)
        service.start()
        XCTAssertTrue(fake.enableCalled, "start() must call enableAndReturnError()")
    }

    func testStartDoesNotThrowWhenReporterFails() {
        let fake = FakePLCrashReporter()
        fake.enableShouldThrow = true
        let service = CrashReporterService(reporter: fake)
        XCTAssertNoThrow(service.start())
    }

    func testNoPendingReportReturnsNil() {
        let fake = FakePLCrashReporter()
        let service = CrashReporterService(reporter: fake)
        XCTAssertNil(service.pendingCrashReport())
    }

    func testPendingReportPurgesAfterLoad() {
        let fake = FakePLCrashReporter()
        fake.hasPending = true
        fake.pendingData = Data([0x00, 0x01])
        let service = CrashReporterService(reporter: fake)
        _ = service.pendingCrashReport()
        XCTAssertTrue(fake.purgeCalled, "Pending report must be purged after load attempt")
    }

    func testNoPendingReportTextReturnsNil() {
        let fake = FakePLCrashReporter()
        let service = CrashReporterService(reporter: fake)
        XCTAssertNil(service.pendingCrashReportText())
    }

    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(CrashReporterService.shared)
    }
}
