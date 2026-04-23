import Foundation
import AppKit

// MARK: - Sparkle User Driver Protocol

/// Protocol mirroring `SPUUserDriver` from the Sparkle framework.
///
/// This abstraction allows the app to integrate with Sparkle's update UI
/// without hard-linking the framework at compile time. When Sparkle is
/// available the concrete `SPUStandardUserDriverAdapter` bridges to it;
/// in environments without Sparkle the `FallbackUpdateDriver` is used.
public protocol SparkleUserDriver: AnyObject {

    /// Show a modal alert informing the user that no update is available.
    func showUpdateNotFound(acknowledgement: @escaping () -> Void)

    /// Present available-update information to the user.
    /// - Parameters:
    ///   - entry: The `AppCastEntry` describing the available release.
    ///   - reply: Called with `true` if the user wants to install, `false` to skip.
    func showUpdateFound(_ entry: AppCastEntry, reply: @escaping (Bool) -> Void)

    /// Report download progress (0.0 – 1.0) to the user.
    func showDownloadProgress(_ fraction: Double)

    /// Notify the user that installation is about to begin.
    /// - Parameter acknowledgement: Called once the user dismisses the prompt.
    func showReadyToInstall(acknowledgement: @escaping () -> Void)

    /// Display an error that occurred during the update process.
    func showUpdateError(_ error: Error)

    /// Dismiss any currently visible update UI.
    func dismissUpdateUI()
}

// MARK: - Standard User Driver (mirrors SPUStandardUserDriver)

/// A concrete `SparkleUserDriver` that presents AppKit alerts — the same UI
/// contract as Sparkle's `SPUStandardUserDriver`.
///
/// When the Sparkle framework is linked this class can be replaced by
/// (or bridge to) `SPUStandardUserDriver` via `SPUStandardUserDriverAdapter`.
/// Until then it provides a fully functional, native update UI out of the box.
public final class SPUStandardUserDriverAdapter: NSObject, SparkleUserDriver {

    // MARK: - State

    private var progressWindow: NSPanel?
    private var progressIndicator: NSProgressIndicator?

    // MARK: - SparkleUserDriver

    public func showUpdateNotFound(acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "You're up to date"
            alert.informativeText = "MiniMaxAgent \(self.currentVersion) is currently the latest version available."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            acknowledgement()
        }
    }

    public func showUpdateFound(_ entry: AppCastEntry, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "A new version of MiniMaxAgent is available!"
            alert.informativeText = """
                MiniMaxAgent \(entry.shortVersion) is now available — you have \(self.currentVersion). \
                Would you like to download it now?
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install Update")
            alert.addButton(withTitle: "Skip This Version")
            alert.addButton(withTitle: "Remind Me Later")

            if let notes = entry.releaseNotes, !notes.isEmpty {
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
                let textView = NSTextView(frame: scrollView.bounds)
                textView.isEditable = false
                textView.string = notes
                scrollView.documentView = textView
                alert.accessoryView = scrollView
            }

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                reply(true)
            default:
                reply(false)
            }
        }
    }

    public func showDownloadProgress(_ fraction: Double) {
        DispatchQueue.main.async {
            if self.progressWindow == nil {
                self.createProgressWindow()
            }
            self.progressIndicator?.doubleValue = fraction * 100
        }
    }

    public func showReadyToInstall(acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.dismissProgressWindow()

            let alert = NSAlert()
            alert.messageText = "Ready to Install"
            alert.informativeText = "MiniMaxAgent has been downloaded and is ready to install. The application will relaunch after installation."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install and Relaunch")
            alert.addButton(withTitle: "Install on Next Launch")
            alert.runModal()
            acknowledgement()
        }
    }

    public func showUpdateError(_ error: Error) {
        DispatchQueue.main.async {
            self.dismissProgressWindow()

            let alert = NSAlert()
            alert.messageText = "Update Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    public func dismissUpdateUI() {
        DispatchQueue.main.async {
            self.dismissProgressWindow()
        }
    }

    // MARK: - Private Helpers

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func createProgressWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Downloading Update…"
        panel.center()

        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 24, width: 320, height: 20))
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 100
        indicator.doubleValue = 0
        indicator.isIndeterminate = false

        panel.contentView?.addSubview(indicator)
        panel.makeKeyAndOrderFront(nil)

        progressWindow = panel
        progressIndicator = indicator
    }

    private func dismissProgressWindow() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
        progressIndicator = nil
    }
}

// MARK: - Update Controller

/// Coordinates update checking and installation using `SparkleUserDriver`.
///
/// This is the entry-point that `AppDelegate` should instantiate. It mirrors
/// the role of `SPUUpdater` in a real Sparkle integration.
public final class SparkleUpdateController {

    // MARK: - Dependencies

    private let configuration: UpdateCheckConfiguration
    private let userDriver: SparkleUserDriver
    private var checkTimer: Timer?

    // MARK: - Initialization

    /// Create a controller with default `SPUStandardUserDriverAdapter`.
    public convenience init(configuration: UpdateCheckConfiguration = .standard) {
        self.init(configuration: configuration, userDriver: SPUStandardUserDriverAdapter())
    }

    /// Create a controller with a custom `SparkleUserDriver` (useful for testing).
    public init(configuration: UpdateCheckConfiguration, userDriver: SparkleUserDriver) {
        self.configuration = configuration
        self.userDriver = userDriver
    }

    // MARK: - Lifecycle

    /// Start automatic update checking according to `configuration`.
    ///
    /// Call this from `applicationDidFinishLaunching(_:)`.
    public func start() {
        guard configuration.isAutomaticCheckEnabled else { return }

        if configuration.checkOnLaunch {
            // Delay first check slightly so the app finishes launching
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.checkForUpdates(userInitiated: false)
            }
        }

        scheduleAutomaticChecks()
    }

    /// Stop automatic update checking.
    public func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Trigger an immediate check for updates (e.g. from a "Check for Updates…" menu item).
    public func checkForUpdatesUserInitiated() {
        checkForUpdates(userInitiated: true)
    }

    // MARK: - Private

    private func scheduleAutomaticChecks() {
        checkTimer?.invalidate()
        let interval = configuration.checkInterval.timeInterval
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForUpdates(userInitiated: false)
        }
    }

    private func checkForUpdates(userInitiated: Bool) {
        guard let feedURL = configuration.updateCheckURL else {
            if userInitiated {
                userDriver.showUpdateNotFound { }
            }
            return
        }

        var request = URLRequest(url: feedURL)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                if userInitiated {
                    self.userDriver.showUpdateError(error)
                }
                return
            }

            guard let data, let xmlString = String(data: data, encoding: .utf8) else {
                if userInitiated {
                    self.userDriver.showUpdateNotFound { }
                }
                return
            }

            let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            let parser = AppCastParser(xml: xmlString)
            guard let latest = parser.latestEntry(), latest.version > currentBuild else {
                if userInitiated {
                    self.userDriver.showUpdateNotFound { }
                }
                return
            }

            self.userDriver.showUpdateFound(latest) { [weak self] accepted in
                guard accepted else { return }
                self?.download(entry: latest)
            }
        }.resume()
    }

    private func download(entry: AppCastEntry) {
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: entry.downloadURL) { [weak self] tempURL, _, error in
            guard let self else { return }

            if let error {
                self.userDriver.showUpdateError(error)
                return
            }

            guard tempURL != nil else { return }

            self.userDriver.showReadyToInstall {
                // In a real Sparkle integration SPUUpdater handles the
                // actual installation. Here we signal completion.
                self.userDriver.dismissUpdateUI()
            }
        }

        // Observe download progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.userDriver.showDownloadProgress(progress.fractionCompleted)
        }

        // Keep the observation alive for the duration of the download
        objc_setAssociatedObject(task, &SparkleUpdateController.observationKey, observation, .OBJC_ASSOCIATION_RETAIN)
        task.resume()
    }

    private static var observationKey: UInt8 = 0
}

// MARK: - AppCast XML Parser

/// Minimal RSS/AppCast parser that extracts `AppCastEntry` values from
/// a Sparkle-format `appcast.xml` feed.
private final class AppCastParser: NSObject, XMLParserDelegate {

    // MARK: - State

    private let xml: String
    private var entries: [AppCastEntry] = []

    // Per-item state
    private var inItem = false
    private var currentVersion: String?
    private var currentShortVersion: String?
    private var currentDownloadURL: URL?
    private var currentLength: Int64 = 0
    private var currentMinOS: String?
    private var currentChannel: String?
    private var currentDate: Date?
    private var currentReleaseNotes: String?
    private var currentElement = ""
    private var currentText = ""

    // MARK: - Init

    init(xml: String) {
        self.xml = xml
    }

    // MARK: - Public

    func latestEntry() -> AppCastEntry? {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return entries.sorted { $0.publishDate > $1.publishDate }.first
    }

    func allEntries() -> [AppCastEntry] {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return entries.sorted { $0.publishDate > $1.publishDate }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "item":
            inItem = true
            currentVersion = nil
            currentShortVersion = nil
            currentDownloadURL = nil
            currentLength = 0
            currentMinOS = nil
            currentChannel = nil
            currentDate = nil
            currentReleaseNotes = nil

        case "enclosure" where inItem:
            if let urlString = attributes["url"] ?? attributes["sparkle:url"],
               let url = URL(string: urlString) {
                currentDownloadURL = url
            }
            if let lengthStr = attributes["sparkle:length"] ?? attributes["length"],
               let length = Int64(lengthStr) {
                currentLength = length
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "sparkle:version":
            currentVersion = text
        case "sparkle:shortVersionString":
            currentShortVersion = text
        case "sparkle:minimumSystemVersion":
            currentMinOS = text
        case "sparkle:channel":
            currentChannel = text
        case "sparkle:releaseNotesLink":
            currentReleaseNotes = text
        case "pubDate":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // RFC 822 / RSS date format
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            currentDate = formatter.date(from: text)
                ?? ISO8601DateFormatter().date(from: text)
                ?? Date()
        case "item":
            inItem = false
            if let version = currentVersion,
               let shortVersion = currentShortVersion,
               let downloadURL = currentDownloadURL {
                let entry = AppCastEntry(
                    version: version,
                    shortVersion: shortVersion,
                    releaseNotes: currentReleaseNotes,
                    downloadURL: downloadURL,
                    downloadLength: currentLength,
                    publishDate: currentDate ?? Date(),
                    minimumSystemVersion: currentMinOS,
                    channel: currentChannel
                )
                entries.append(entry)
            }
        default:
            break
        }
    }
}
