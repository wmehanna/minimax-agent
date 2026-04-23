import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Sparkle-compatible update controller using SPUStandardUserDriverAdapter.
    private let updateController = SparkleUpdateController(
        configuration: .standard
    )

    /// Uploads pending crash reports to the diagnostics server on launch.
    private let crashReportUploadService: CrashReportUploadService = {
        let endpointURL = URL(string: "https://diagnostics.minimaxagent.app/v1/crashes")!
        let config = CrashReportUploadService.Config(endpointURL: endpointURL)
        return CrashReportUploadService(config: config)
    }()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register crash signal handlers before any background work begins
        SignalHandler.register()

        // Enable crash reporting before anything else so that any crash
        // during the remainder of launch is captured.
        CrashReporterService.shared.start()
        processPendingCrashReport()

        // Start automatic update checking via Sparkle-compatible driver
        updateController.start()

        // Upload any pending crash reports in the background
        Task {
            await crashReportUploadService.uploadPendingReports()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateController.stop()
    }

    // MARK: - Menu Actions

    /// Connected to "Check for Updates…" in the application menu.
    @IBAction func checkForUpdates(_ sender: Any?) {
        updateController.checkForUpdatesUserInitiated()
    }

    // MARK: - Private

    /// Loads any crash report from the previous run and logs it to stderr.
    private func processPendingCrashReport() {
        guard let text = CrashReporterService.shared.pendingCrashReportText() else { return }
        fputs("[CrashReporterService] Previous crash report:\n\(text)\n", stderr)
    }
}
