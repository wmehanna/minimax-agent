import XCTest

// MARK: - XCUIApplicationLaunchTests
//
// UI tests covering XCUIApplication launch and termination lifecycle
// for the MiniMaxAgent macOS application.

final class XCUIApplicationLaunchTests: XCTestCase {

    // MARK: - Properties

    var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }

    // MARK: - Launch

    func testAppLaunchesSuccessfully() throws {
        app.launch()
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground after launch")
    }

    func testAppLaunchWithDefaultArguments() throws {
        app.launch()
        XCTAssertEqual(app.bundleIdentifier, "com.minimaxagent.app")
    }

    func testAppLaunchWithLaunchArguments() throws {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testAppLaunchWithLaunchEnvironment() throws {
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testAppWindowExistsAfterLaunch() throws {
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.exists, "At least one window should exist after launch")
    }

    // MARK: - Termination

    func testAppTerminatesSuccessfully() throws {
        app.launch()
        XCTAssertTrue(app.state == .runningForeground)

        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App should not be running after terminate()")
    }

    func testAppCanRelaunchAfterTermination() throws {
        app.launch()
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)

        app.launch()
        XCTAssertTrue(app.state == .runningForeground, "App should relaunch successfully after prior termination")
    }

    func testTerminateFromNotRunningStateIsNoop() throws {
        // App has never been launched — terminate should be safe
        XCTAssertEqual(app.state, .notRunning)
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }

    // MARK: - State Transitions

    func testAppStateIsNotRunningBeforeLaunch() throws {
        XCTAssertEqual(app.state, .notRunning)
    }

    func testAppStateTransitionLaunchToTerminate() throws {
        XCTAssertEqual(app.state, .notRunning)

        app.launch()
        XCTAssertTrue(app.state == .runningForeground)

        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }
}
