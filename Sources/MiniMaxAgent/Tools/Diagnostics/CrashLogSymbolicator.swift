import Foundation

// MARK: - Crash Log Symbolication
//
// Phase 8: Performance & Reliability — Crash log symbolication
// Task 8.3: Symbolicate crash logs using atos and symbolicatecrash
//
// Provides utilities for symbolicating macOS crash logs by:
// - Parsing .crash / .ips files from ~/Library/Logs/DiagnosticReports
// - Invoking `atos` with the dSYM or binary to resolve addresses
// - Producing human-readable stack traces

// MARK: - Types

/// A single symbolicated frame in a crash stack trace.
public struct SymbolicatedFrame: Sendable, Equatable {
    /// Thread number the frame belongs to.
    public let threadIndex: Int
    /// Frame number within the thread.
    public let frameIndex: Int
    /// Binary image name (e.g. "MiniMaxAgent").
    public let binaryName: String
    /// Raw load address string from the crash log.
    public let loadAddress: String
    /// Human-readable symbol resolved by `atos`, or `nil` if resolution failed.
    public let symbol: String?

    public init(
        threadIndex: Int,
        frameIndex: Int,
        binaryName: String,
        loadAddress: String,
        symbol: String? = nil
    ) {
        self.threadIndex = threadIndex
        self.frameIndex = frameIndex
        self.binaryName = binaryName
        self.loadAddress = loadAddress
        self.symbol = symbol
    }

    /// Returns the symbol if available, otherwise the raw load address.
    public var displayName: String {
        symbol ?? loadAddress
    }
}

/// The result of symbolicating a crash log file.
public struct SymbolicationResult: Sendable {
    /// Path to the original crash file.
    public let crashFilePath: String
    /// All symbolicated frames, in order.
    public let frames: [SymbolicatedFrame]
    /// Any errors encountered during symbolication.
    public let errors: [String]
    /// Whether symbolication completed without errors.
    public var isSuccessful: Bool { errors.isEmpty }

    public init(crashFilePath: String, frames: [SymbolicatedFrame], errors: [String]) {
        self.crashFilePath = crashFilePath
        self.frames = frames
        self.errors = errors
    }
}

/// Errors thrown by `CrashLogSymbolicator`.
public enum SymbolicationError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case unreadableFile(String)
    case binaryNotFound(String)
    case atosNotAvailable
    case symbolicationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Crash file not found: \(path)"
        case .unreadableFile(let path):
            return "Cannot read crash file: \(path)"
        case .binaryNotFound(let name):
            return "Binary or dSYM not found for: \(name)"
        case .atosNotAvailable:
            return "`atos` tool is not available on this system"
        case .symbolicationFailed(let detail):
            return "Symbolication failed: \(detail)"
        }
    }
}

// MARK: - Crash Log Parser

/// Parses Apple crash report (.crash / .ips) files and extracts stack frames.
public struct CrashLogParser: Sendable {

    // Matches lines like:
    //   0   MiniMaxAgent    0x000000010012abcd 0x100000000 + 77789
    private static let framePattern = #/^(\d+)\s+(\S+)\s+(0x[0-9a-fA-F]+)\s+.*$/#

    public init() {}

    /// Parse a crash log file and return raw (un-symbolicated) frames.
    /// - Parameters:
    ///   - path: Absolute path to the .crash or .ips file.
    ///   - targetBinary: Only include frames from this binary (nil = all).
    /// - Returns: Array of frames with symbol set to nil.
    /// - Throws: `SymbolicationError` on file access failures.
    public func parseFrames(at path: String, targetBinary: String? = nil) throws -> [SymbolicatedFrame] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SymbolicationError.fileNotFound(path)
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw SymbolicationError.unreadableFile(path)
        }

        var frames: [SymbolicatedFrame] = []
        var currentThread = 0

        for line in content.components(separatedBy: .newlines) {
            // Track thread boundaries
            if line.hasPrefix("Thread ") && line.contains(":") {
                let parts = line.components(separatedBy: " ")
                if let idx = parts.dropFirst().first.flatMap(Int.init) {
                    currentThread = idx
                }
                continue
            }

            guard let match = line.firstMatch(of: Self.framePattern) else { continue }

            let frameIdx = Int(match.1) ?? 0
            let binaryName = String(match.2)
            let address = String(match.3)

            if let target = targetBinary, binaryName != target { continue }

            frames.append(SymbolicatedFrame(
                threadIndex: currentThread,
                frameIndex: frameIdx,
                binaryName: binaryName,
                loadAddress: address
            ))
        }

        return frames
    }

    /// Locate the slide address for a binary in the crash log's Binary Images section.
    /// - Parameters:
    ///   - content: Full text of the crash log.
    ///   - binaryName: Name of the binary to find.
    /// - Returns: The load address string, or nil if not found.
    public func slideAddress(in content: String, for binaryName: String) -> String? {
        // Binary Images block lines look like:
        //   0x100000000 - 0x10012ffff MiniMaxAgent arm64  <uuid> /path/to/binary
        let pattern = #/^\s*(0x[0-9a-fA-F]+)\s+-\s+0x[0-9a-fA-F]+\s+\#(binaryName)\s/#
        for line in content.components(separatedBy: .newlines) {
            if let match = line.firstMatch(of: pattern) {
                return String(match.1)
            }
        }
        return nil
    }
}

// MARK: - Symbolication Engine

/// Symbolicates crash log frames using the `atos` command-line tool.
///
/// ## Usage
/// ```swift
/// let symbolica = CrashLogSymbolicator()
/// let result = try await symbolica.symbolicate(
///     crashFile: "/path/to/MiniMaxAgent-2026-03-30.crash",
///     binaryPath: "/path/to/MiniMaxAgent.app/Contents/MacOS/MiniMaxAgent"
/// )
/// for frame in result.frames {
///     print("\(frame.frameIndex): \(frame.displayName)")
/// }
/// ```
public struct CrashLogSymbolicator: Sendable {

    private let parser: CrashLogParser

    public init(parser: CrashLogParser = CrashLogParser()) {
        self.parser = parser
    }

    // MARK: - Public API

    /// Symbolicate all frames in a crash log using `atos`.
    ///
    /// - Parameters:
    ///   - crashFile: Absolute path to the .crash or .ips file.
    ///   - binaryPath: Path to the binary or dSYM bundle to symbolicate against.
    ///   - targetBinary: Restrict symbolication to frames of this binary name (optional).
    /// - Returns: `SymbolicationResult` containing all resolved frames.
    /// - Throws: `SymbolicationError` if the crash file cannot be read or `atos` is unavailable.
    public func symbolicate(
        crashFile: String,
        binaryPath: String,
        targetBinary: String? = nil
    ) async throws -> SymbolicationResult {
        guard FileManager.default.fileExists(atPath: crashFile) else {
            throw SymbolicationError.fileNotFound(crashFile)
        }
        guard let crashContent = try? String(contentsOfFile: crashFile, encoding: .utf8) else {
            throw SymbolicationError.unreadableFile(crashFile)
        }

        // Verify atos is available
        guard isAtosAvailable() else {
            throw SymbolicationError.atosNotAvailable
        }

        let rawFrames = try parser.parseFrames(at: crashFile, targetBinary: targetBinary)

        guard !rawFrames.isEmpty else {
            return SymbolicationResult(crashFilePath: crashFile, frames: [], errors: [])
        }

        // Group frames by binary for batched atos invocations
        let framesByBinary = Dictionary(grouping: rawFrames, by: \.binaryName)
        var symbolicated: [SymbolicatedFrame] = []
        var errors: [String] = []

        for (binary, frames) in framesByBinary {
            let slideAddr = parser.slideAddress(in: crashContent, for: binary)
            let resolved = await resolveFrames(
                frames,
                binaryPath: binaryPath,
                slideAddress: slideAddr,
                errors: &errors
            )
            symbolicated.append(contentsOf: resolved)
        }

        // Restore original order
        symbolicated.sort {
            if $0.threadIndex != $1.threadIndex { return $0.threadIndex < $1.threadIndex }
            return $0.frameIndex < $1.frameIndex
        }

        return SymbolicationResult(
            crashFilePath: crashFile,
            frames: symbolicated,
            errors: errors
        )
    }

    /// Find crash logs for the given process name in `~/Library/Logs/DiagnosticReports`.
    /// - Parameter processName: The process name to search for (e.g. "MiniMaxAgent").
    /// - Returns: Paths to matching .crash and .ips files, sorted newest-first.
    public func findCrashLogs(for processName: String) -> [String] {
        let diagnosticsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: diagnosticsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let matching = contents.filter { url in
            let name = url.lastPathComponent
            let ext = url.pathExtension
            return (ext == "crash" || ext == "ips") && name.hasPrefix(processName)
        }

        return matching
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB
            }
            .map(\.path)
    }

    // MARK: - Private

    private func isAtosAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["atos"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func resolveFrames(
        _ frames: [SymbolicatedFrame],
        binaryPath: String,
        slideAddress: String?,
        errors: inout [String]
    ) async -> [SymbolicatedFrame] {
        let addresses = frames.map(\.loadAddress)

        var args = ["-o", binaryPath]
        if let slide = slideAddress {
            args += ["-l", slide]
        }
        args += addresses

        let output = runAtos(arguments: args)

        guard let output else {
            errors.append("atos failed for binary: \(binaryPath)")
            return frames
        }

        let symbols = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return zip(frames, symbols).map { frame, sym in
            SymbolicatedFrame(
                threadIndex: frame.threadIndex,
                frameIndex: frame.frameIndex,
                binaryName: frame.binaryName,
                loadAddress: frame.loadAddress,
                symbol: sym.isEmpty ? nil : sym
            )
        } + frames.dropFirst(symbols.count)
    }

    private func runAtos(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/atos")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Convenience

extension CrashLogSymbolicator {

    /// Symbolicate the most recent crash log for the given process.
    ///
    /// - Parameters:
    ///   - processName: The process name (e.g. "MiniMaxAgent").
    ///   - binaryPath: Path to the binary or dSYM bundle.
    /// - Returns: `SymbolicationResult` or `nil` if no crash logs were found.
    public func symbolicateMostRecent(
        processName: String,
        binaryPath: String
    ) async throws -> SymbolicationResult? {
        guard let latest = findCrashLogs(for: processName).first else {
            return nil
        }
        return try await symbolicate(
            crashFile: latest,
            binaryPath: binaryPath,
            targetBinary: processName
        )
    }
}
