import Foundation

/// Error thrown when a timeout occurs
public struct TimeoutError: Error, LocalizedError, Sendable {
    /// The operation that timed out
    public let operation: String

    /// The timeout duration
    public let durationSeconds: Double

    public var errorDescription: String? {
        "Operation '\(operation)' timed out after \(String(format: "%.1f", durationSeconds)) seconds"
    }

    public init(operation: String, durationSeconds: Double) {
        self.operation = operation
        self.durationSeconds = durationSeconds
    }
}

/// Configuration for timeout behavior
public struct TimeoutConfig: Sendable, Equatable {
    /// Default timeout in seconds (0 = no timeout)
    public let defaultTimeout: Double

    /// Whether to kill the process on timeout (if applicable)
    public let killOnTimeout: Bool

    /// Custom timeout per operation name (takes precedence over default)
    public let perOperationTimeout: [String: Double]

    public init(
        defaultTimeout: Double = 0,
        killOnTimeout: Bool = true,
        perOperationTimeout: [String: Double] = [:]
    ) {
        self.defaultTimeout = defaultTimeout
        self.killOnTimeout = killOnTimeout
        self.perOperationTimeout = perOperationTimeout
    }

    /// Standard configuration with sensible defaults
    public static let standard = TimeoutConfig(
        defaultTimeout: 300, // 5 minutes
        killOnTimeout: true,
        perOperationTimeout: [:]
    )

    /// No timeout configuration
    public static let none = TimeoutConfig(
        defaultTimeout: 0,
        killOnTimeout: false,
        perOperationTimeout: [:]
    )
}

/// Result of a timed operation
public struct TimedResult<T: Sendable>: Sendable {
    /// The result value if successful
    public let value: T?

    /// The error if the operation failed
    public let error: Error?

    /// Whether the operation timed out
    public let timedOut: Bool

    /// The actual duration of the operation
    public let actualDurationSeconds: Double

    /// Whether the operation succeeded
    public var success: Bool { error == nil && !timedOut }

    public init(value: T?, error: Error?, timedOut: Bool, actualDurationSeconds: Double) {
        self.value = value
        self.error = error
        self.timedOut = timedOut
        self.actualDurationSeconds = actualDurationSeconds
    }
}

/// TimeoutManager provides timeout handling for operations
///
/// Manages timeouts for various operations including command execution,
/// with support for per-operation custom timeouts and automatic cleanup.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: timeout handling
///
/// Usage:
///   let manager = TimeoutManager(config: .standard)
///   let result = manager.execute(command: "sleep 10", cwd: "/tmp")
///   if result.timedOut {
///       print("Command timed out after \(result.actualDurationSeconds)s")
///   }
///
/// Async usage:
///   let timedResult = try await manager.withTimeout("network-call", duration: 5.0) {
///       try await someAsyncOperation()
///   }
public struct TimeoutManager: Sendable {

    public let config: TimeoutConfig

    /// Shared default manager
    public static let `default` = TimeoutManager(config: .standard)

    public init(config: TimeoutConfig = .standard) {
        self.config = config
    }

    // MARK: - Execute with Timeout (Sync)

    /// Execute a shell command with timeout handling
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - cwd: The working directory
    ///   - operationName: Name for timeout reporting (defaults to command)
    ///   - customTimeout: Optional custom timeout for this specific operation
    /// - Returns: TimedResult containing the command result
    public func execute(
        command: String,
        cwd: String,
        operationName: String? = nil,
        customTimeout: Double? = nil
    ) -> TimedResult<CommandResult> {
        let opName = operationName ?? command
        let timeout = resolveTimeout(for: opName, custom: customTimeout)

        if timeout <= 0 {
            // No timeout - execute directly
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = ExecuteCommandTool.execute(command: command, cwd: cwd)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            return TimedResult(
                value: result,
                error: nil,
                timedOut: false,
                actualDurationSeconds: duration * 1000
            )
        }

        // Execute with timeout using semaphore
        let startTime = CFAbsoluteTimeGetCurrent()
        var timedOut = false
        var result: CommandResult?

        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            result = ExecuteCommandTool(options: ExecuteCommandOptions(timeoutSeconds: Int(timeout) + 1)).execute(command: command, cwd: cwd)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + .seconds(Int(timeout)))

        if waitResult == .timedOut {
            timedOut = true
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            return TimedResult(
                value: nil,
                error: TimeoutError(operation: opName, durationSeconds: timeout),
                timedOut: true,
                actualDurationSeconds: duration
            )
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        return TimedResult(
            value: result,
            error: nil,
            timedOut: timedOut,
            actualDurationSeconds: duration
        )
    }

    /// Execute a block with timeout
    /// - Parameters:
    ///   - operationName: Name for timeout reporting
    ///   - duration: Timeout in seconds
    ///   - block: The operation to execute
    /// - Returns: TimedResult containing the result
    public func withTimeout<T>(
        operation operationName: String,
        duration: Double,
        _ block: @escaping () throws -> T
    ) -> TimedResult<T> {
        let startTime = CFAbsoluteTimeGetCurrent()
        var timedOut = false
        var result: T?
        var thrownError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                result = try block()
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + .seconds(Int(duration)))

        if waitResult == .timedOut {
            timedOut = true
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            return TimedResult(
                value: nil,
                error: TimeoutError(operation: operationName, durationSeconds: duration),
                timedOut: true,
                actualDurationSeconds: duration
            )
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        return TimedResult(
            value: result,
            error: thrownError,
            timedOut: false,
            actualDurationSeconds: duration
        )
    }

    // MARK: - Execute with Timeout (Async)

    /// Execute an async block with timeout
    /// - Parameters:
    ///   - operationName: Name for timeout reporting
    ///   - duration: Timeout in seconds
    ///   - block: The async operation to execute
    /// - Returns: TimedResult containing the result
    @available(macOS 12.0, *)
    public func withTimeout<T>(
        operation operationName: String,
        duration: Double,
        _ block: @escaping () async throws -> T
    ) async -> TimedResult<T> {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await block()
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    throw TimeoutError(operation: operationName, durationSeconds: duration)
                }

                guard let result = try await group.next() else {
                    throw TimeoutError(operation: operationName, durationSeconds: duration)
                }

                group.cancelAll()
                return result
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            return TimedResult(
                value: result,
                error: nil,
                timedOut: false,
                actualDurationSeconds: duration
            )
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let isTimeout = error is TimeoutError
            return TimedResult(
                value: nil,
                error: error,
                timedOut: isTimeout,
                actualDurationSeconds: duration
            )
        }
    }

    // MARK: - Private Helpers

    private func resolveTimeout(for operation: String, custom: Double?) -> Double {
        if let custom = custom {
            return custom
        }
        if let perOp = config.perOperationTimeout[operation] {
            return perOp
        }
        return config.defaultTimeout
    }
}

// MARK: - Convenience Extensions

extension TimeoutManager {

    /// Execute with no timeout
    public func executeWithoutTimeout(command: String, cwd: String) -> CommandResult {
        let result = execute(command: command, cwd: cwd, operationName: nil, customTimeout: 0)
        return result.value ?? CommandResult(
            command: command,
            workingDirectory: cwd,
            exitCode: -1,
            stdout: "",
            stderr: "Command failed to execute",
            durationMs: 0
        )
    }

    /// Execute with a specific timeout
    public func executeWithTimeout(command: String, cwd: String, timeoutSeconds: Double) -> TimedResult<CommandResult> {
        execute(command: command, cwd: cwd, customTimeout: timeoutSeconds)
    }

    /// Create a manager with custom per-operation timeouts
    public func withOperationTimeouts(_ timeouts: [String: Double]) -> TimeoutManager {
        let config = self.config
        var newPerOp = config.perOperationTimeout
        for (key, value) in timeouts {
            newPerOp[key] = value
        }
        let newConfig = TimeoutConfig(
            defaultTimeout: config.defaultTimeout,
            killOnTimeout: config.killOnTimeout,
            perOperationTimeout: newPerOp
        )
        return TimeoutManager(config: newConfig)
    }
}

// MARK: - Global Helper

/// Execute a command with a timeout
/// - Parameters:
///   - command: The shell command to execute
///   - cwd: The working directory
///   - timeoutSeconds: Timeout in seconds (0 = no timeout)
/// - Returns: CommandResult (note: this does not indicate if it timed out, use TimeoutManager for full results)
public func execute_with_timeout(command: String, cwd: String, timeoutSeconds: Double) -> CommandResult {
    if timeoutSeconds <= 0 {
        return ExecuteCommandTool.execute(command: command, cwd: cwd)
    }

    let manager = TimeoutManager(config: TimeoutConfig(defaultTimeout: timeoutSeconds, killOnTimeout: true))
    let result = manager.execute(command: command, cwd: cwd)
    return result.value ?? CommandResult(
        command: command,
        workingDirectory: cwd,
        exitCode: -1,
        stdout: result.timedOut ? "" : (result.error?.localizedDescription ?? ""),
        stderr: result.timedOut ? "Command timed out after \(timeoutSeconds) seconds" : (result.error?.localizedDescription ?? ""),
        durationMs: Int64(result.actualDurationSeconds * 1000)
    )
}
