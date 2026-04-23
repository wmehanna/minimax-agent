import Foundation

/// Error thrown when all retry attempts are exhausted
public struct RetryExhaustedError: Error, LocalizedError, Sendable {
    /// The command that was being executed
    public let command: String

    /// The working directory
    public let workingDirectory: String

    /// Number of attempts made
    public let attempts: Int

    /// The last exit code received
    public let lastExitCode: Int32

    /// The last error message
    public let lastError: String

    public var errorDescription: String? {
        "Command '\(command)' failed after \(attempts) attempts (last exit code: \(lastExitCode)): \(lastError)"
    }

    public init(
        command: String,
        workingDirectory: String,
        attempts: Int,
        lastExitCode: Int32,
        lastError: String
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.attempts = attempts
        self.lastExitCode = lastExitCode
        self.lastError = lastError
    }
}

/// Error thrown when a retryable operation times out
public struct RetryTimeoutError: Error, LocalizedError, Sendable {
    public let command: String
    public let attempts: Int
    public let totalDuration: Double

    public var errorDescription: String? {
        "Command '\(command)' timed out after \(attempts) attempts and \(String(format: "%.1f", totalDuration))s"
    }
}

/// Strategy for calculating delays between retry attempts
public enum BackoffStrategy: Sendable {
    /// Linear backoff: delay = baseDelay * attempt
    case linear(baseDelay: TimeInterval)

    /// Exponential backoff: delay = baseDelay * (multiplier ^ attempt)
    case exponential(baseDelay: TimeInterval, multiplier: Double)

    /// Fixed delay between attempts
    case fixed(delay: TimeInterval)

    /// No delay (immediate retry)
    case none

    /// Calculate delay for a given attempt (1-indexed)
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        switch self {
        case .linear(let baseDelay):
            return baseDelay * Double(attempt)
        case .exponential(let baseDelay, let multiplier):
            return baseDelay * pow(multiplier, Double(attempt - 1))
        case .fixed(let delay):
            return delay
        case .none:
            return 0
        }
    }
}

/// Condition for determining if a command should be retried
public enum RetryCondition: Sendable {
    /// Never retry
    case never

    /// Retry on any non-zero exit code
    case onNonZeroExitCode

    /// Retry on specific exit codes
    case onExitCodes(Set<Int32>)

    /// Retry on any error
    case onAnyError

    /// Custom retry condition
    case custom((Int32, String) -> Bool)

    /// Check if the given exit code should trigger a retry
    public func shouldRetry(exitCode: Int32, stderr: String) -> Bool {
        switch self {
        case .never:
            return false
        case .onNonZeroExitCode:
            return exitCode != 0
        case .onExitCodes(let codes):
            return codes.contains(exitCode)
        case .onAnyError:
            return exitCode != 0 || !stderr.isEmpty
        case .custom(let predicate):
            return predicate(exitCode, stderr)
        }
    }
}

/// Configuration for retry behavior
public struct RetryConfig: Sendable {
    /// Maximum number of attempts (including the first attempt)
    public let maxAttempts: Int

    /// Initial delay before first retry
    public let initialDelay: TimeInterval

    /// Backoff strategy
    public let backoff: BackoffStrategy

    /// Jitter factor (0.0 to 1.0) to add randomness to delays
    public let jitterFactor: Double

    /// Condition for determining if a retry should be attempted
    public let retryCondition: RetryCondition

    /// Whether to include attempt count in error messages
    public let includeAttemptInError: Bool

    /// Timeout per attempt (0 = no timeout)
    public let timeoutPerAttempt: TimeInterval

    /// Whether to backoff on timeout as well
    public let backoffOnTimeout: Bool

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        backoff: BackoffStrategy = .exponential(baseDelay: 1.0, multiplier: 2.0),
        jitterFactor: Double = 0.1,
        retryCondition: RetryCondition = .onNonZeroExitCode,
        includeAttemptInError: Bool = true,
        timeoutPerAttempt: TimeInterval = 0,
        backoffOnTimeout: Bool = true
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.backoff = backoff
        self.jitterFactor = jitterFactor
        self.retryCondition = retryCondition
        self.includeAttemptInError = includeAttemptInError
        self.timeoutPerAttempt = timeoutPerAttempt
        self.backoffOnTimeout = backoffOnTimeout
    }

    /// Default retry config: 3 attempts with exponential backoff starting at 1s
    public static let standard = RetryConfig(
        maxAttempts: 3,
        initialDelay: 1.0,
        backoff: .exponential(baseDelay: 1.0, multiplier: 2.0),
        jitterFactor: 0.1
    )

    /// Aggressive retry: 5 attempts with faster backoff
    public static let aggressive = RetryConfig(
        maxAttempts: 5,
        initialDelay: 0.5,
        backoff: .exponential(baseDelay: 0.5, multiplier: 1.5),
        jitterFactor: 0.15
    )

    /// Conservative retry: fewer attempts with longer delays
    public static let conservative = RetryConfig(
        maxAttempts: 2,
        initialDelay: 2.0,
        backoff: .exponential(baseDelay: 2.0, multiplier: 3.0),
        jitterFactor: 0.2
    )

    /// No retry
    public static let none = RetryConfig(
        maxAttempts: 1,
        retryCondition: .never
    )
}

/// Result of a retry operation
public struct RetryResult<T: Sendable>: Sendable {
    /// The successful result (if any)
    public let value: T?

    /// Whether the operation succeeded
    public let succeeded: Bool

    /// Number of attempts made
    public let attempts: Int

    /// Total duration of all attempts
    public let totalDuration: TimeInterval

    /// All exit codes received
    public let exitCodes: [Int32]

    /// The final error if all retries failed
    public let error: Error?

    /// Results from each attempt
    public let attemptResults: [T]

    public init(
        value: T?,
        succeeded: Bool,
        attempts: Int,
        totalDuration: TimeInterval,
        exitCodes: [Int32],
        error: Error?,
        attemptResults: [T] = []
    ) {
        self.value = value
        self.succeeded = succeeded
        self.attempts = attempts
        self.totalDuration = totalDuration
        self.exitCodes = exitCodes
        self.error = error
        self.attemptResults = attemptResults
    }

    /// Check if result is from a successful retry
    public var isSuccess: Bool { succeeded }

    /// Get the last successful result or nil
    public var lastValue: T? { value ?? attemptResults.last }
}

/// CommandRetryHandler provides retry logic with backoff for command execution
///
/// Executes commands with automatic retry on failure, supporting configurable
/// backoff strategies and retry conditions.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Command retry logic (3 attempts with backoff)
///
/// Usage:
///   let handler = CommandRetryHandler(config: .standard)
///   let result = handler.execute(command: "make", cwd: "/project")
///   if !result.succeeded {
///       print("Failed after \(result.attempts) attempts: \(result.error)")
///   }
public struct CommandRetryHandler: Sendable {

    public let config: RetryConfig

    public init(config: RetryConfig = .standard) {
        self.config = config
    }

    // MARK: - Execute with Retry

    /// Execute a command with retry logic
    /// - Parameters:
    ///   - command: The command to execute
    ///   - cwd: Working directory
    ///   - operationName: Name for logging/debugging
    /// - Returns: RetryResult containing the final result
    public func execute(
        command: String,
        cwd: String,
        operationName: String? = nil
    ) -> RetryResult<CommandResult> {
        let startTime = CFAbsoluteTimeGetCurrent()
        var attempts: [CommandResult] = []
        var exitCodes: [Int32] = []

        for attempt in 1...config.maxAttempts {
            let attemptStartTime = CFAbsoluteTimeGetCurrent()

            // Execute the command
            let result: CommandResult
            if config.timeoutPerAttempt > 0 {
                let tool = ExecuteCommandTool(options: ExecuteCommandOptions(timeoutSeconds: Int(config.timeoutPerAttempt)))
                result = tool.execute(command: command, cwd: cwd)
            } else {
                result = ExecuteCommandTool.execute(command: command, cwd: cwd)
            }

            let attemptDuration = CFAbsoluteTimeGetCurrent() - attemptStartTime
            attempts.append(result)
            exitCodes.append(result.exitCode)

            // Check if we should retry
            let shouldRetry = attempt < config.maxAttempts &&
                config.retryCondition.shouldRetry(exitCode: result.exitCode, stderr: result.stderr)

            if !shouldRetry {
                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                return RetryResult(
                    value: result,
                    succeeded: result.success,
                    attempts: attempt,
                    totalDuration: totalDuration,
                    exitCodes: exitCodes,
                    error: result.success ? nil : ExitCodeError(
                        command: command,
                        workingDirectory: cwd,
                        exitCode: result.exitCode,
                        stderr: result.stderr
                    ),
                    attemptResults: attempts
                )
            }

            // Calculate delay before next retry
            if attempt < config.maxAttempts {
                var delay = config.backoff.delay(forAttempt: attempt)

                // Add jitter
                if config.jitterFactor > 0 {
                    let jitter = delay * config.jitterFactor * Double.random(in: -1...1)
                    delay = max(0, delay + jitter)
                }

                // Wait before retry
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        // All attempts exhausted
        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        let lastResult = attempts.last!

        return RetryResult(
            value: nil,
            succeeded: false,
            attempts: attempts.count,
            totalDuration: totalDuration,
            exitCodes: exitCodes,
            error: RetryExhaustedError(
                command: command,
                workingDirectory: cwd,
                attempts: attempts.count,
                lastExitCode: lastResult.exitCode,
                lastError: lastResult.stderr.isEmpty ? "Non-zero exit code \(lastResult.exitCode)" : lastResult.stderr
            ),
            attemptResults: attempts
        )
    }

    /// Execute with retry and throw on failure
    /// - Parameters:
    ///   - command: The command to execute
    ///   - cwd: Working directory
    /// - Returns: The successful CommandResult
    /// - Throws: RetryExhaustedError if all retries fail
    public func executeOrThrow(
        command: String,
        cwd: String
    ) throws -> CommandResult {
        let result = execute(command: command, cwd: cwd)
        if result.succeeded, let value = result.value {
            return value
        }
        throw result.error ?? RetryExhaustedError(
            command: command,
            workingDirectory: cwd,
            attempts: result.attempts,
            lastExitCode: result.exitCodes.last ?? -1,
            lastError: "Unknown error"
        )
    }

    // MARK: - Async Execute with Retry

    /// Execute an async operation with retry logic
    /// - Parameters:
    ///   - operationName: Name for logging/debugging
    ///   - operation: The async operation to execute
    /// - Returns: RetryResult containing the final result
    @available(macOS 12.0, *)
    public func executeAsync<T: Sendable>(
        operation operationName: String,
        timeout: TimeInterval = 0,
        _ operation: @escaping () async throws -> T
    ) async -> RetryResult<T> {
        let startTime = CFAbsoluteTimeGetCurrent()
        var attempts: [T] = []
        var errors: [Error] = []

        for attempt in 1...config.maxAttempts {
            do {
                let result: T
                if timeout > 0 {
                    result = try await withTimeout(operation: operationName, duration: timeout, operation)
                } else {
                    result = try await operation()
                }

                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                return RetryResult(
                    value: result,
                    succeeded: true,
                    attempts: attempt,
                    totalDuration: totalDuration,
                    exitCodes: [],
                    error: nil,
                    attemptResults: attempts + [result]
                )
            } catch {
                errors.append(error)

                // Check if we should retry
                let shouldRetry = attempt < config.maxAttempts

                if !shouldRetry {
                    let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                    return RetryResult(
                        value: nil,
                        succeeded: false,
                        attempts: attempt,
                        totalDuration: totalDuration,
                        exitCodes: [],
                        error: error,
                        attemptResults: attempts
                    )
                }

                // Calculate delay before next retry
                var delay = config.backoff.delay(forAttempt: attempt)
                if config.jitterFactor > 0 {
                    let jitter = delay * config.jitterFactor * Double.random(in: -1...1)
                    delay = max(0, delay + jitter)
                }

                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        return RetryResult(
            value: nil,
            succeeded: false,
            attempts: config.maxAttempts,
            totalDuration: totalDuration,
            exitCodes: [],
            error: errors.last,
            attemptResults: attempts
        )
    }

    @available(macOS 12.0, *)
    private func withTimeout<T>(
        operation name: String,
        duration: TimeInterval,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                throw TimeoutError(operation: name, durationSeconds: duration)
            }

            guard let result = try await group.next() else {
                throw TimeoutError(operation: name, durationSeconds: duration)
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - Convenience Extensions

extension CommandRetryHandler {

    /// Create a handler with custom retry condition
    public func retryWhen(_ condition: @escaping (Int32, String) -> Bool) -> CommandRetryHandler {
        var newConfig = config
        let newRetryConfig = RetryConfig(
            maxAttempts: config.maxAttempts,
            initialDelay: config.initialDelay,
            backoff: config.backoff,
            jitterFactor: config.jitterFactor,
            retryCondition: .custom(condition),
            includeAttemptInError: config.includeAttemptInError,
            timeoutPerAttempt: config.timeoutPerAttempt,
            backoffOnTimeout: config.backoffOnTimeout
        )
        return CommandRetryHandler(config: newRetryConfig)
    }

    /// Execute with custom exit codes to retry on
    public func retryOnExitCodes(_ codes: Set<Int32>) -> CommandRetryHandler {
        var newRetryConfig = RetryConfig(
            maxAttempts: config.maxAttempts,
            initialDelay: config.initialDelay,
            backoff: config.backoff,
            jitterFactor: config.jitterFactor,
            retryCondition: .onExitCodes(codes),
            includeAttemptInError: config.includeAttemptInError,
            timeoutPerAttempt: config.timeoutPerAttempt,
            backoffOnTimeout: config.backoffOnTimeout
        )
        return CommandRetryHandler(config: newRetryConfig)
    }
}

// MARK: - Global Helper

/// Execute a command with default retry logic (3 attempts with exponential backoff)
/// - Parameters:
///   - command: The command to execute
///   - cwd: Working directory
/// - Returns: RetryResult containing the final result
public func execute_command_with_retry(
    command: String,
    cwd: String
) -> RetryResult<CommandResult> {
    let handler = CommandRetryHandler(config: .standard)
    return handler.execute(command: command, cwd: cwd)
}
