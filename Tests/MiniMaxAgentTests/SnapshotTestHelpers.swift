import XCTest

// MARK: - Snapshot Testing Helpers
//
// Lightweight file-based snapshot testing. Snapshots are stored as plain text
// files under Tests/MiniMaxAgentTests/Snapshots/<name>.txt
//
// Record mode: set environment variable SNAPSHOT_RECORD_MODE=1 to write/overwrite.
// Verify mode (default): compare actual value against stored snapshot.

private let snapshotsDirectory: URL = {
    // Resolve relative to this source file so snapshots travel with the repo.
    let thisFile = URL(fileURLWithPath: #file)
    return thisFile
        .deletingLastPathComponent()
        .appendingPathComponent("Snapshots")
}()

private var isRecordMode: Bool {
    ProcessInfo.processInfo.environment["SNAPSHOT_RECORD_MODE"] == "1"
}

func assertSnapshot(
    _ value: String,
    name: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    let snapshotURL = snapshotsDirectory.appendingPathComponent("\(name).txt")

    if isRecordMode {
        do {
            try FileManager.default.createDirectory(
                at: snapshotsDirectory,
                withIntermediateDirectories: true
            )
            try value.write(to: snapshotURL, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to write snapshot '\(name)': \(error)", file: file, line: line)
        }
        return
    }

    guard let stored = try? String(contentsOf: snapshotURL, encoding: .utf8) else {
        XCTFail(
            "No snapshot found for '\(name)'. Run with SNAPSHOT_RECORD_MODE=1 to create it.",
            file: file,
            line: line
        )
        return
    }

    XCTAssertEqual(
        value,
        stored,
        "Snapshot mismatch for '\(name)'",
        file: file,
        line: line
    )
}
