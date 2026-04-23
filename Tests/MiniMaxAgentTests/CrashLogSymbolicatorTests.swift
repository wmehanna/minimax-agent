import XCTest
@testable import MiniMaxAgent

final class CrashLogSymbolicatorTests: XCTestCase {

    // MARK: - CrashLogParser Tests

    func testParseFramesReturnsEmptyForMissingFile() {
        let parser = CrashLogParser()
        XCTAssertThrowsError(try parser.parseFrames(at: "/nonexistent/path.crash")) { error in
            guard case SymbolicationError.fileNotFound = error else {
                XCTFail("Expected fileNotFound, got \(error)")
                return
            }
        }
    }

    func testParseFramesExtractsAddresses() throws {
        let crashContent = """
        Thread 0 Crashed:
        0   MiniMaxAgent    0x0000000100012abc 0x100000000 + 77788
        1   MiniMaxAgent    0x0000000100034def 0x100000000 + 143839
        2   libdyld.dylib   0x00007ff80012abcd 0x7ff80012a000 + 3021

        Thread 1:
        0   libsystem_kernel.dylib  0x00007ff8001dead0 0x7ff80019a000 + 85712

        Binary Images:
           0x100000000 - 0x10012ffff MiniMaxAgent arm64  <ABC123> /Applications/MiniMaxAgent.app/Contents/MacOS/MiniMaxAgent
        """

        let tmpFile = NSTemporaryDirectory() + "test_crash_\(UUID().uuidString).crash"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try crashContent.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let parser = CrashLogParser()
        let allFrames = try parser.parseFrames(at: tmpFile)
        XCTAssertEqual(allFrames.count, 4)

        let miniMaxFrames = try parser.parseFrames(at: tmpFile, targetBinary: "MiniMaxAgent")
        XCTAssertEqual(miniMaxFrames.count, 2)
        XCTAssertEqual(miniMaxFrames[0].loadAddress, "0x0000000100012abc")
        XCTAssertEqual(miniMaxFrames[1].loadAddress, "0x0000000100034def")
    }

    func testParseFramesAssignsThreadIndex() throws {
        let crashContent = """
        Thread 0 Crashed:
        0   MiniMaxAgent    0x0000000100012abc 0x100000000 + 77788

        Thread 2:
        0   MiniMaxAgent    0x0000000100034def 0x100000000 + 143839
        """

        let tmpFile = NSTemporaryDirectory() + "test_thread_\(UUID().uuidString).crash"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try crashContent.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let parser = CrashLogParser()
        let frames = try parser.parseFrames(at: tmpFile)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].threadIndex, 0)
        XCTAssertEqual(frames[1].threadIndex, 2)
    }

    func testSlideAddressExtraction() {
        let content = """
        Binary Images:
           0x100000000 - 0x10012ffff MiniMaxAgent arm64  <UUID> /path/MiniMaxAgent
           0x7ff80012a000 - 0x7ff800130fff libdyld.dylib x86_64 <UUID2> /usr/lib/libdyld.dylib
        """

        let parser = CrashLogParser()
        let slide = parser.slideAddress(in: content, for: "MiniMaxAgent")
        XCTAssertEqual(slide, "0x100000000")

        let missingSlide = parser.slideAddress(in: content, for: "NonExistent")
        XCTAssertNil(missingSlide)
    }

    // MARK: - SymbolicatedFrame Tests

    func testDisplayNameUsesSymbolWhenAvailable() {
        let frameWithSymbol = SymbolicatedFrame(
            threadIndex: 0,
            frameIndex: 0,
            binaryName: "MiniMaxAgent",
            loadAddress: "0x100012abc",
            symbol: "main() in main.swift:42"
        )
        XCTAssertEqual(frameWithSymbol.displayName, "main() in main.swift:42")
    }

    func testDisplayNameFallsBackToAddress() {
        let frameNoSymbol = SymbolicatedFrame(
            threadIndex: 0,
            frameIndex: 1,
            binaryName: "MiniMaxAgent",
            loadAddress: "0x100012abc"
        )
        XCTAssertEqual(frameNoSymbol.displayName, "0x100012abc")
    }

    // MARK: - CrashLogSymbolicator Tests

    func testSymbolicatorThrowsForMissingFile() async {
        let symbolica = CrashLogSymbolicator()
        do {
            _ = try await symbolica.symbolicate(
                crashFile: "/no/such/file.crash",
                binaryPath: "/usr/bin/true"
            )
            XCTFail("Expected error to be thrown")
        } catch SymbolicationError.fileNotFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFindCrashLogsReturnsEmptyForUnknownProcess() {
        let symbolica = CrashLogSymbolicator()
        let logs = symbolica.findCrashLogs(for: "ZZZNoSuchProcess_XYZ_12345")
        XCTAssertTrue(logs.isEmpty)
    }

    func testSymbolicationResultIsSuccessfulWithNoErrors() {
        let result = SymbolicationResult(crashFilePath: "/tmp/test.crash", frames: [], errors: [])
        XCTAssertTrue(result.isSuccessful)
    }

    func testSymbolicationResultIsNotSuccessfulWithErrors() {
        let result = SymbolicationResult(
            crashFilePath: "/tmp/test.crash",
            frames: [],
            errors: ["atos failed"]
        )
        XCTAssertFalse(result.isSuccessful)
    }

    func testSymbolicateEmptyCrashLogReturnsEmptyFrames() async throws {
        let tmpFile = NSTemporaryDirectory() + "empty_\(UUID().uuidString).crash"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try "No stack frames here.".write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let symbolica = CrashLogSymbolicator()
        let result = try await symbolica.symbolicate(
            crashFile: tmpFile,
            binaryPath: "/usr/bin/true"
        )
        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertTrue(result.isSuccessful)
    }
}
