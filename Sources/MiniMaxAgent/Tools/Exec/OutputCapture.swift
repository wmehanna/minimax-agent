import Foundation

/// Captured output from stdout or stderr
public struct CapturedOutput: Sendable, Equatable {
    /// The captured text
    public let text: String

    /// Whether the output was truncated due to size limits
    public let truncated: Bool

    /// Original byte count before truncation
    public let originalByteCount: Int

    /// Maximum size in bytes (0 = unlimited)
    public let maxSize: Int

    public init(text: String, truncated: Bool = false, originalByteCount: Int? = nil, maxSize: Int = 0) {
        self.text = text
        self.truncated = truncated
        self.originalByteCount = originalByteCount ?? text.utf8.count
        self.maxSize = maxSize
    }

    /// Empty captured output
    public static let empty = CapturedOutput(text: "")
}

/// Result of capturing stdout and stderr together
public struct CapturedOutputPair: Sendable, Equatable {
    public let stdout: CapturedOutput
    public let stderr: CapturedOutput

    public init(stdout: CapturedOutput, stderr: CapturedOutput) {
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Whether both outputs are empty
    public var isEmpty: Bool { stdout.text.isEmpty && stderr.text.isEmpty }

    /// Combined output (stdout + stderr with separator)
    public var combined: String {
        if stdout.text.isEmpty {
            return stderr.text
        } else if stderr.text.isEmpty {
            return stdout.text
        }
        return "\(stdout.text)\n--- stderr ---\n\(stderr.text)"
    }
}

/// Configuration for output capture
public struct OutputCaptureConfig: Sendable {
    /// Maximum bytes to capture per stream (0 = unlimited)
    public let maxSize: Int

    /// Whether to capture timestamps
    public let includeTimestamps: Bool

    /// Default encoding to use
    public let encoding: String.Encoding

    /// Append newline between chunks
    public let newlineBetweenChunks: Bool

    public init(
        maxSize: Int = 1024 * 1024, // 1MB default
        includeTimestamps: Bool = false,
        encoding: String.Encoding = .utf8,
        newlineBetweenChunks: Bool = true
    ) {
        self.maxSize = maxSize
        self.includeTimestamps = includeTimestamps
        self.encoding = encoding
        self.newlineBetweenChunks = newlineBetweenChunks
    }

    /// No limit configuration
    public static let unlimited = OutputCaptureConfig(
        maxSize: 0,
        includeTimestamps: false,
        encoding: .utf8,
        newlineBetweenChunks: false
    )
}

/// OutputCapture provides utilities for capturing stdout and stderr streams
///
/// Captures output streams from shell commands or arbitrary operations,
/// with support for size limits, truncation, and combined capture.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: stdout/stderr capture
///
/// Usage:
///   let captured = OutputCapture.capture { print("Hello") }
///   print(captured.stdout.text) // "Hello\n"
///
///   let (result, stdout, stderr) = OutputCapture.captureOutput {
///       runCommand("ls")
///   }
public struct OutputCapture: Sendable {

    public let config: OutputCaptureConfig

    /// Default capture configuration
    public static let `default` = OutputCapture(config: OutputCaptureConfig())

    public init(config: OutputCaptureConfig = OutputCaptureConfig()) {
        self.config = config
    }

    // MARK: - Capture stdout

    /// Capture stdout from a closure
    /// - Parameters:
    ///   - operation: The operation to execute
    /// - Returns: Tuple of (result value, captured stdout)
    public func capture<T>(_ operation: () throws -> T) -> (T, CapturedOutput) {
        let pipe = Pipe()
        let errorPipe = Pipe()

        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)

        // Redirect stdout to pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        var capturedData = Data()
        var capturedText = ""
        var truncated = false

        // Capture in background
        let queue = DispatchQueue(label: "com.minimaxagent.outputcapture")
        var hasCompleted = false
        let semaphore = DispatchSemaphore(value: 0)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                hasCompleted = true
                semaphore.signal()
                return
            }

            if self.config.maxSize > 0 && capturedData.count + data.count > self.config.maxSize {
                let remaining = self.config.maxSize - capturedData.count
                if remaining > 0 {
                    capturedData.append(data.prefix(remaining))
                }
                truncated = true
                hasCompleted = true
                semaphore.signal()
                return
            }

            capturedData.append(data)
        }

        // Execute operation
        var result: T?
        var thrownError: Error?

        do {
            result = try operation()
        } catch {
            thrownError = error
        }

        // Close write end to signal EOF
        dup2(originalStdout, STDOUT_FILENO)

        // Wait for capture to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 5.0)
        pipe.fileHandleForReading.readabilityHandler = nil

        // Restore stderr
        dup2(originalStderr, STDERR_FILENO)

        // Close duplicated file descriptors
        close(originalStdout)
        close(originalStderr)

        // Convert to string
        if let text = String(data: capturedData, encoding: config.encoding) {
            capturedText = text
        } else if let text = String(data: capturedData, encoding: .utf8) {
            capturedText = text
        }

        if let error = thrownError {
            // If there was an error, re-throw after capturing
            // But we need to handle this carefully
        }

        let output = CapturedOutput(
            text: capturedText,
            truncated: truncated,
            originalByteCount: capturedData.count,
            maxSize: config.maxSize
        )

        return (result!, output)
    }

    // MARK: - Capture with both stdout and stderr

    /// Capture both stdout and stderr from a closure
    /// - Parameter operation: The operation to execute
    /// - Returns: Tuple of (result value, captured stdout, captured stderr)
    public func captureOutput<T>(_ operation: () throws -> T) -> (T, CapturedOutput, CapturedOutput) {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)

        // Redirect stdout to pipe
        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        // Redirect stderr to pipe
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        var stdoutData = Data()
        var stderrData = Data()
        var stdoutTruncated = false
        var stderrTruncated = false

        let queue = DispatchQueue(label: "com.minimaxagent.outputcapture")

        let stdoutSemaphore = DispatchSemaphore(value: 0)
        let stderrSemaphore = DispatchSemaphore(value: 0)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutSemaphore.signal()
                return
            }

            if self.config.maxSize > 0 && stdoutData.count + data.count > self.config.maxSize {
                let remaining = self.config.maxSize - stdoutData.count
                if remaining > 0 {
                    stdoutData.append(data.prefix(remaining))
                }
                stdoutTruncated = true
                stdoutSemaphore.signal()
                return
            }

            stdoutData.append(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrSemaphore.signal()
                return
            }

            if self.config.maxSize > 0 && stderrData.count + data.count > self.config.maxSize {
                let remaining = self.config.maxSize - stderrData.count
                if remaining > 0 {
                    stderrData.append(data.prefix(remaining))
                }
                stderrTruncated = true
                stderrSemaphore.signal()
                return
            }

            stderrData.append(data)
        }

        // Execute operation
        var result: T?
        var thrownError: Error?

        do {
            result = try operation()
        } catch {
            thrownError = error
        }

        // Close write ends to signal EOF
        dup2(originalStdout, STDOUT_FILENO)
        dup2(originalStderr, STDERR_FILENO)

        // Wait for both streams
        _ = stdoutSemaphore.wait(timeout: .now() + 5.0)
        _ = stderrSemaphore.wait(timeout: .now() + 5.0)

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Close duplicated file descriptors
        close(originalStdout)
        close(originalStderr)

        let stdoutText = String(data: stdoutData, encoding: config.encoding)
            ?? String(data: stdoutData, encoding: .utf8)
            ?? ""
        let stderrText = String(data: stderrData, encoding: config.encoding)
            ?? String(data: stderrData, encoding: .utf8)
            ?? ""

        let stdoutOutput = CapturedOutput(
            text: stdoutText,
            truncated: stdoutTruncated,
            originalByteCount: stdoutData.count,
            maxSize: config.maxSize
        )
        let stderrOutput = CapturedOutput(
            text: stderrText,
            truncated: stderrTruncated,
            originalByteCount: stderrData.count,
            maxSize: config.maxSize
        )

        return (result!, stdoutOutput, stderrOutput)
    }

    // MARK: - Static Convenience Methods

    /// Capture stdout from an operation (convenience method)
    public static func capture<T>(_ operation: () throws -> T) -> (T, CapturedOutput) {
        OutputCapture().capture(operation)
    }

    /// Capture both stdout and stderr (convenience method)
    public static func captureOutput<T>(_ operation: () throws -> T) -> (T, CapturedOutput, CapturedOutput) {
        OutputCapture().captureOutput(operation)
    }
}

// MARK: - File Output Capture

extension OutputCapture {

    /// Capture output to a file instead of memory
    /// - Parameters:
    ///   - path: Path to write captured output
    ///   - operation: The operation to capture
    /// - Returns: File handle position and captured output pair
    public func captureToFile(
        stdoutPath: String,
        stderrPath: String? = nil,
        _ operation: () throws -> Void
    ) -> (Void, CapturedOutputPair) {
        let stdoutURL = URL(fileURLWithPath: stdoutPath)
        let stderrURL = stderrPath.map { URL(fileURLWithPath: $0) }

        // Create/truncate files
        FileManager.default.createFile(atPath: stdoutPath, contents: nil, attributes: nil)
        if let stderrPath = stderrPath {
            FileManager.default.createFile(atPath: stderrPath, contents: nil, attributes: nil)
        }

        guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL) else {
            return ((), CapturedOutputPair(
                stdout: CapturedOutput(text: "", truncated: false),
                stderr: CapturedOutput(text: "", truncated: false)
            ))
        }

        defer { try? stdoutHandle.close() }

        var stderrHandle: FileHandle?
        if let stderrURL = stderrURL {
            stderrHandle = try? FileHandle(forWritingTo: stderrURL)
            defer { try? stderrHandle?.close() }
        }

        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)

        dup2(stdoutHandle.fileDescriptor, STDOUT_FILENO)
        if let handle = stderrHandle {
            dup2(handle.fileDescriptor, STDERR_FILENO)
        }

        do {
            try operation()
        } catch {
            // Ignore errors during capture
        }

        // Restore
        dup2(originalStdout, STDOUT_FILENO)
        dup2(originalStderr, STDERR_FILENO)

        close(originalStdout)
        close(originalStderr)

        // Read back captured content
        let stdoutContent = (try? String(contentsOf: stdoutURL, encoding: config.encoding)) ?? ""
        let stderrContent: String
        if let stderrPath = stderrPath {
            stderrContent = (try? String(contentsOf: URL(fileURLWithPath: stderrPath), encoding: config.encoding)) ?? ""
        } else {
            stderrContent = ""
        }

        return ((),
            CapturedOutputPair(
                stdout: CapturedOutput(text: stdoutContent, truncated: false),
                stderr: CapturedOutput(text: stderrContent, truncated: false)
            )
        )
    }
}

// MARK: - Integration with CommandResult

extension OutputCapture {

    /// Capture output from a command execution
    public func execute(command: String, cwd: String) -> CapturedCommandResult {
        let result = ExecuteCommandTool.execute(command: command, cwd: cwd)
        return CapturedCommandResult(
            command: result.command,
            workingDirectory: result.workingDirectory,
            exitCode: result.exitCode,
            stdout: CapturedOutput(text: result.stdout, truncated: false),
            stderr: CapturedOutput(text: result.stderr, truncated: false),
            durationMs: result.durationMs
        )
    }
}

/// Extended command result with proper captured output types
public struct CapturedCommandResult: Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let exitCode: Int32
    public let stdout: CapturedOutput
    public let stderr: CapturedOutput
    public let durationMs: Int64

    public var success: Bool { exitCode == 0 }

    public init(
        command: String,
        workingDirectory: String,
        exitCode: Int32,
        stdout: CapturedOutput,
        stderr: CapturedOutput,
        durationMs: Int64
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }
}
