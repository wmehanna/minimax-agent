import Foundation
import CrashReporter

// MARK: - CrashReporterService

/// Wraps PLCrashReporter to provide crash detection and pending-report collection.
///
/// Call `start()` once from `applicationDidFinishLaunching(_:)`.  Any crash
/// report written in a previous run is available via `pendingCrashReport()`
/// and can be forwarded to a remote logging endpoint.
public final class CrashReporterService {

    // MARK: - Shared

    public static let shared = CrashReporterService()

    // MARK: - Properties

    private let reporter: PLCrashReporter

    // MARK: - Initialization

    /// Creates a service backed by the default `PLCrashReporter` instance.
    public init(reporter: PLCrashReporter = .shared()) {
        self.reporter = reporter
    }

    // MARK: - Lifecycle

    /// Enables the crash reporter.
    ///
    /// - Important: Call exactly once, before any other application code runs.
    public func start() {
        do {
            try reporter.enableAndReturnError()
        } catch {
            fputs("[CrashReporterService] Failed to enable PLCrashReporter: \(error)\n", stderr)
        }
    }

    // MARK: - Pending Report

    /// Returns the crash report written during the previous run, if any.
    ///
    /// The report is purged from disk after being returned so subsequent calls
    /// return `nil` until another crash occurs.
    public func pendingCrashReport() -> PLCrashReport? {
        guard reporter.hasPendingCrashReport() else { return nil }

        defer { reporter.purgePendingCrashReport() }

        do {
            let data = try reporter.loadPendingCrashReportDataAndReturnError()
            return try PLCrashReport(data: data)
        } catch {
            fputs("[CrashReporterService] Failed to load pending crash report: \(error)\n", stderr)
            return nil
        }
    }

    // MARK: - Formatted Report

    /// Returns the pending crash report as a human-readable string, or `nil`.
    public func pendingCrashReportText() -> String? {
        guard let report = pendingCrashReport() else { return nil }
        return PLCrashReportTextFormatter.stringValue(
            for: report,
            with: PLCrashReportTextFormatiOS
        )
    }
}
