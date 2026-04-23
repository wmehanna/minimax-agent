import Foundation

/// Service for collecting and uploading crash reports to a remote server.
///
/// Crash reports are gathered from macOS diagnostic directories and uploaded
/// via HTTP POST using the shared `RateLimitedHTTPClient`. Reports that have
/// already been uploaded are tracked so they are not sent twice.
///
/// ## Usage
/// ```swift
/// let service = CrashReportUploadService(endpointURL: url)
/// await service.uploadPendingReports()
/// ```
public actor CrashReportUploadService {

    // MARK: - Configuration

    /// Configuration for the crash report upload service.
    public struct Config: Sendable {
        /// The remote endpoint that accepts crash report payloads (HTTP POST).
        public let endpointURL: URL

        /// Maximum number of reports uploaded per invocation.
        public let maxReportsPerBatch: Int

        /// Maximum age of a crash report to consider for upload (seconds).
        public let maxReportAge: TimeInterval

        /// HTTP client configuration forwarded to `RateLimitedHTTPClient`.
        public let httpConfig: RateLimitedHTTPClient.Config

        public init(
            endpointURL: URL,
            maxReportsPerBatch: Int = 10,
            maxReportAge: TimeInterval = 7 * 24 * 3600,
            httpConfig: RateLimitedHTTPClient.Config = .standard
        ) {
            self.endpointURL = endpointURL
            self.maxReportsPerBatch = maxReportsPerBatch
            self.maxReportAge = maxReportAge
            self.httpConfig = httpConfig
        }
    }

    // MARK: - Payload

    /// JSON payload sent for each crash report.
    public struct CrashReportPayload: Sendable, Codable, Equatable {
        /// Bundle identifier of the crashed application.
        public let bundleIdentifier: String

        /// Short version string (CFBundleShortVersionString).
        public let appVersion: String

        /// Build number (CFBundleVersion).
        public let buildNumber: String

        /// macOS version string.
        public let osVersion: String

        /// Name of the .crash / .ips file.
        public let reportFileName: String

        /// UTC timestamp when the crash occurred (ISO 8601).
        public let crashDate: String

        /// Raw crash report content.
        public let reportContent: String

        public init(
            bundleIdentifier: String,
            appVersion: String,
            buildNumber: String,
            osVersion: String,
            reportFileName: String,
            crashDate: String,
            reportContent: String
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.appVersion = appVersion
            self.buildNumber = buildNumber
            self.osVersion = osVersion
            self.reportFileName = reportFileName
            self.crashDate = crashDate
            self.reportContent = reportContent
        }
    }

    // MARK: - Upload Result

    /// Outcome of a single crash report upload attempt.
    public enum UploadResult: Sendable, Equatable {
        case uploaded(fileName: String)
        case skipped(fileName: String, reason: SkipReason)
        case failed(fileName: String, error: String)
    }

    /// Reason a report was skipped without attempting upload.
    public enum SkipReason: Sendable, Equatable {
        case alreadyUploaded
        case tooOld
        case readError
    }

    // MARK: - Errors

    public enum UploadError: Error, LocalizedError, Sendable {
        case encodingFailed(String)
        case serverError(Int, String)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed(let msg):
                return "Failed to encode crash report payload: \(msg)"
            case .serverError(let code, let msg):
                return "Server returned \(code): \(msg)"
            }
        }
    }

    // MARK: - Properties

    private let config: Config
    private let httpClient: RateLimitedHTTPClient
    private let fileManager: FileManager
    private var uploadedFileNames: Set<String>

    /// Key used to persist the set of already-uploaded report file names.
    private static let uploadedReportsDefaultsKey = "com.minimaxagent.crashreports.uploaded"

    // MARK: - Initialization

    /// Initialize with a configuration.
    /// - Parameter config: Upload service configuration.
    public init(config: Config) {
        self.config = config
        self.httpClient = RateLimitedHTTPClient(config: config.httpConfig)
        self.fileManager = .default
        self.uploadedFileNames = Set(
            UserDefaults.standard.stringArray(
                forKey: CrashReportUploadService.uploadedReportsDefaultsKey
            ) ?? []
        )
    }

    // MARK: - Public API

    /// Scan macOS crash log directories and upload any new reports.
    /// - Returns: An array of `UploadResult` values, one per report found.
    @discardableResult
    public func uploadPendingReports() async -> [UploadResult] {
        let reportURLs = collectCrashReportURLs()
        var results: [UploadResult] = []

        for url in reportURLs.prefix(config.maxReportsPerBatch) {
            let fileName = url.lastPathComponent

            // Skip already-uploaded reports
            guard !uploadedFileNames.contains(fileName) else {
                results.append(.skipped(fileName: fileName, reason: .alreadyUploaded))
                continue
            }

            // Skip reports that are too old
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let modDate = attributes[.modificationDate] as? Date {
                let age = Date().timeIntervalSince(modDate)
                if age > config.maxReportAge {
                    results.append(.skipped(fileName: fileName, reason: .tooOld))
                    continue
                }
            }

            // Read report content
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                results.append(.skipped(fileName: fileName, reason: .readError))
                continue
            }

            let result = await upload(fileName: fileName, content: content)
            results.append(result)
        }

        return results
    }

    // MARK: - Private Helpers

    /// Collect .crash and .ips files from standard macOS diagnostic directories.
    private func collectCrashReportURLs() -> [URL] {
        let directories = crashReportDirectories()
        var urls: [URL] = []

        for dir in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            let reports = contents.filter {
                $0.pathExtension == "crash" || $0.pathExtension == "ips"
            }
            urls.append(contentsOf: reports)
        }

        // Sort newest first
        return urls.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }
    }

    /// Standard macOS directories that contain crash reports for the current user.
    private func crashReportDirectories() -> [URL] {
        var dirs: [URL] = []

        // ~/Library/Logs/DiagnosticReports
        let home = fileManager.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent("Library/Logs/DiagnosticReports"))

        // /Library/Logs/DiagnosticReports (system-wide, may require elevated access)
        dirs.append(URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"))

        return dirs
    }

    /// Build a payload and POST it to the configured endpoint.
    private func upload(fileName: String, content: String) async -> UploadResult {
        let payload = buildPayload(fileName: fileName, content: content)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bodyData = try encoder.encode(payload)

            let response = try await httpClient.post(
                config.endpointURL.absoluteString,
                body: bodyData,
                contentType: "application/json"
            )

            guard response.isSuccess else {
                let serverMessage = String(data: response.body, encoding: .utf8) ?? ""
                return .failed(
                    fileName: fileName,
                    error: UploadError.serverError(response.statusCode, serverMessage).localizedDescription
                )
            }

            markAsUploaded(fileName: fileName)
            return .uploaded(fileName: fileName)

        } catch let error as UploadError {
            return .failed(fileName: fileName, error: error.localizedDescription)
        } catch {
            return .failed(fileName: fileName, error: error.localizedDescription)
        }
    }

    /// Construct a `CrashReportPayload` from the file content and app metadata.
    private func buildPayload(fileName: String, content: String) -> CrashReportPayload {
        let bundle = Bundle.main
        let bundleId = bundle.bundleIdentifier ?? "com.minimaxagent.app"
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // Attempt to extract the crash date from the report header
        let crashDate = extractCrashDate(from: content) ?? iso8601Now()

        return CrashReportPayload(
            bundleIdentifier: bundleId,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            reportFileName: fileName,
            crashDate: crashDate,
            reportContent: content
        )
    }

    /// Mark a report file as uploaded and persist the set.
    private func markAsUploaded(fileName: String) {
        uploadedFileNames.insert(fileName)
        UserDefaults.standard.set(
            Array(uploadedFileNames),
            forKey: CrashReportUploadService.uploadedReportsDefaultsKey
        )
    }

    /// Parse the "Date/Time:" field from a .crash report header.
    private func extractCrashDate(from content: String) -> String? {
        for line in content.split(separator: "\n", maxSplits: 30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Date/Time:") {
                let value = trimmed
                    .dropFirst("Date/Time:".count)
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// ISO 8601 timestamp for the current moment.
    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
