import Foundation

/// Git-specific transient errors that should trigger a retry
public enum GitTransientError: Error, Sendable {
    /// Lock file exists (another git operation in progress)
    case lockFileExists

    /// Remote repository is not available
    case remoteNotAvailable

    /// Network timeout or connection failure
    case networkFailure

    /// Push rejected due to non-fast-forward (might succeed after pull)
    case pushRejected

    /// Authentication failed (token might have been refreshed)
    case authenticationFailed

    /// SSL certificate problem
    case sslCertificateError

    /// RPC failed (GitHub/GitLab API issues)
    case rpcFailed

    /// Unknown transient error with stderr context
    case unknown(String)

    /// Check if stderr indicates a transient error
    public static func fromStderr(_ stderr: String, exitCode: Int32) -> GitTransientError? {
        let lowercased = stderr.lowercased()

        // Lock file
        if lowercased.contains("index.lock") || lowercased.contains("unable to lock") {
            return .lockFileExists
        }

        // Network failures
        if lowercased.contains("connection timed out") ||
           lowercased.contains("connection refused") ||
           lowercased.contains("network is unreachable") ||
           lowercased.contains("could not resolve host") ||
           lowercased.contains("failed to connect") {
            return .networkFailure
        }

        // Remote not available
        if lowercased.contains("remote not found") ||
           lowercased.contains("repository not found") ||
           lowercased.contains("could not read from remote") {
            return .remoteNotAvailable
        }

        // Push rejected
        if lowercased.contains("push rejected") ||
           lowercased.contains("non-fast-forward") ||
           lowercased.contains("updates were rejected") {
            return .pushRejected
        }

        // Auth failures
        if lowercased.contains("authentication failed") ||
           lowercased.contains("could not authenticate") ||
           lowercased.contains("403") {
            return .authenticationFailed
        }

        // SSL errors
        if lowercased.contains("ssl") && (lowercased.contains("error") || lowercased.contains("certificate")) {
            return .sslCertificateError
        }

        // RPC failures (GitHub/GitLab API)
        if lowercased.contains("rpc failed") ||
           lowercased.contains("http") && lowercased.contains("500") ||
           lowercased.contains("http") && lowercased.contains("502") ||
           lowercased.contains("http") && lowercased.contains("503") {
            return .rpcFailed
        }

        // Check exit code for other transient failures
        let retryableExitCodes: Set<Int32> = [128, 1]
        if retryableExitCodes.contains(exitCode) && !stderr.isEmpty {
            return .unknown(stderr)
        }

        return nil
    }
}

/// Result of a Git operation with retry information
public struct GitOperationRetryResult: Sendable {
    /// Whether the operation succeeded
    public let succeeded: Bool

    /// Number of attempts made
    public let attempts: Int

    /// Total duration
    public let totalDuration: TimeInterval

    /// The final output (stdout)
    public let output: String

    /// The final error output (stderr)
    public let errorOutput: String

    /// Exit code
    public let exitCode: Int32

    /// The command that was executed
    public let command: String

    /// Working directory
    public let workingDirectory: String

    /// All transient errors encountered
    public let transientErrors: [GitTransientError]

    /// Final error if all retries failed
    public let error: Error?

    public init(
        succeeded: Bool,
        attempts: Int,
        totalDuration: TimeInterval,
        output: String,
        errorOutput: String,
        exitCode: Int32,
        command: String,
        workingDirectory: String,
        transientErrors: [GitTransientError] = [],
        error: Error? = nil
    ) {
        self.succeeded = succeeded
        self.attempts = attempts
        self.totalDuration = totalDuration
        self.output = output
        self.errorOutput = errorOutput
        self.exitCode = exitCode
        self.command = command
        self.workingDirectory = workingDirectory
        self.transientErrors = transientErrors
        self.error = error
    }

    public var isSuccess: Bool { succeeded }
}

/// Configuration for Git operation retries
public struct GitRetryConfig: Sendable {
    /// Maximum number of attempts (including first)
    public let maxAttempts: Int

    /// Initial delay in seconds
    public let initialDelay: TimeInterval

    /// Backoff multiplier for exponential backoff
    public let backoffMultiplier: Double

    /// Maximum delay between retries
    public let maxDelay: TimeInterval

    /// Whether to handle lock files by waiting
    public let handleLockFiles: Bool

    /// Maximum time to wait for lock file to be released
    public let lockFileWaitTimeout: TimeInterval

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        maxDelay: TimeInterval = 30.0,
        handleLockFiles: Bool = true,
        lockFileWaitTimeout: TimeInterval = 60.0
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.backoffMultiplier = backoffMultiplier
        self.maxDelay = maxDelay
        self.handleLockFiles = handleLockFiles
        self.lockFileWaitTimeout = lockFileWaitTimeout
    }

    /// Default Git retry config
    public static let standard = GitRetryConfig()

    /// Aggressive retry for unstable networks
    public static let aggressive = GitRetryConfig(
        maxAttempts: 5,
        initialDelay: 0.5,
        backoffMultiplier: 1.5,
        maxDelay: 60.0
    )

    /// Conservative retry
    public static let conservative = GitRetryConfig(
        maxAttempts: 2,
        initialDelay: 2.0,
        backoffMultiplier: 3.0,
        maxDelay: 30.0
    )
}

/// GitOperationRetry provides retry logic specifically for Git operations
///
/// Detects transient failures (network issues, lock files, push rejections) and
/// automatically retries with appropriate backoff.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Git operation retry on transient failures
///
/// Usage:
///   let retry = GitOperationRetry(config: .standard)
///   let result = retry.execute(gitCommand: ["push", "origin", "main"], cwd: "/project")
///   if !result.succeeded {
///       print("Push failed after \(result.attempts) attempts")
///   }
public struct GitOperationRetry: Sendable {

    public let config: GitRetryConfig

    public init(config: GitRetryConfig = .standard) {
        self.config = config
    }

    // MARK: - Execute Git Command with Retry

    /// Execute a git command with automatic retry on transient failures
    /// - Parameters:
    ///   - gitCommand: The git command arguments (e.g., ["push", "origin", "main"])
    ///   - cwd: Working directory for the git command
    ///   - remote: Optional remote URL to use instead of configured remote
    /// - Returns: GitOperationRetryResult with outcome details
    public func execute(
        gitCommand: [String],
        cwd: String,
        remote: String? = nil
    ) -> GitOperationRetryResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let command = "git " + gitCommand.joined(separator: " ")
        var attempts = 0
        var transientErrors: [GitTransientError] = []
        var lastOutput = ""
        var lastErrorOutput = ""
        var lastExitCode: Int32 = 0

        for attempt in 1...config.maxAttempts {
            attempts = attempt

            // Handle lock file if present
            if config.handleLockFiles {
                handleLockFileIfPresent(in: cwd)
            }

            // Execute git command
            let result = executeGitCommand(gitCommand, cwd: cwd, remote: remote)
            lastOutput = result.output
            lastErrorOutput = result.stderr
            lastExitCode = result.exitCode

            // Check if successful
            if result.exitCode == 0 {
                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                return GitOperationRetryResult(
                    succeeded: true,
                    attempts: attempts,
                    totalDuration: totalDuration,
                    output: lastOutput,
                    errorOutput: lastErrorOutput,
                    exitCode: 0,
                    command: command,
                    workingDirectory: cwd,
                    transientErrors: transientErrors
                )
            }

            // Check if transient error
            if let transientError = GitTransientError.fromStderr(result.stderr, exitCode: result.exitCode) {
                transientErrors.append(transientError)

                // Don't retry on certain errors
                switch transientError {
                case .pushRejected:
                    // Push rejection usually needs rebase/fetch/merge, don't auto-retry
                    break
                default:
                    // Retry other transient errors
                    if attempt < config.maxAttempts {
                        let delay = calculateDelay(forAttempt: attempt)
                        Thread.sleep(forTimeInterval: delay)
                        continue
                    }
                }
            }

            // Non-transient error or last attempt
            break
        }

        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        return GitOperationRetryResult(
            succeeded: false,
            attempts: attempts,
            totalDuration: totalDuration,
            output: lastOutput,
            errorOutput: lastErrorOutput,
            exitCode: lastExitCode,
            command: command,
            workingDirectory: cwd,
            transientErrors: transientErrors,
            error: GitOperationError(
                command: command,
                exitCode: lastExitCode,
                stderr: lastErrorOutput,
                attempts: attempts
            )
        )
    }

    /// Execute git pull with retry
    public func pull(cwd: String, remote: String = "origin", branch: String? = nil) -> GitOperationRetryResult {
        var args = ["pull", remote]
        if let branch = branch {
            args.append(branch)
        }
        return execute(gitCommand: args, cwd: cwd, remote: remote)
    }

    /// Execute git push with retry
    public func push(cwd: String, remote: String = "origin", branch: String? = nil) -> GitOperationRetryResult {
        var args = ["push", remote]
        if let branch = branch {
            args.append(branch)
        }
        return execute(gitCommand: args, cwd: cwd, remote: remote)
    }

    /// Execute git fetch with retry
    public func fetch(cwd: String, remote: String? = nil) -> GitOperationRetryResult {
        var args = ["fetch"]
        if let remote = remote {
            args.append(remote)
        }
        return execute(gitCommand: args, cwd: cwd, remote: remote)
    }

    /// Execute git clone with retry
    public func clone(url: String, cwd: String) -> GitOperationRetryResult {
        return execute(gitCommand: ["clone", url, "."], cwd: cwd)
    }

    // MARK: - Private Helpers

    private func executeGitCommand(_ args: [String], cwd: String, remote: String?) -> (output: String, stderr: String, exitCode: Int32) {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        var output = ""
        var errorOutput = ""
        var exitCode: Int32 = 0

        do {
            try task.run()
            task.waitUntilExit()
            exitCode = task.terminationStatus
        } catch {
            errorOutput = "Failed to execute git: \(error.localizedDescription)"
            return (output, errorOutput, -1)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        output = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        return (output, errorOutput, exitCode)
    }

    private func calculateDelay(forAttempt attempt: Int) -> TimeInterval {
        var delay = config.initialDelay * pow(config.backoffMultiplier, Double(attempt - 1))
        delay = min(delay, config.maxDelay)
        // Add small random jitter to prevent thundering herd
        let jitter = delay * 0.1 * Double.random(in: -1...1)
        return max(0, delay + jitter)
    }

    private func handleLockFileIfPresent(in cwd: String) {
        let lockPath = (cwd as NSString).appendingPathComponent(".git/index.lock")
        let lockURL = URL(fileURLWithPath: lockPath)

        if FileManager.default.fileExists(atPath: lockPath) {
            // Wait briefly for lock to be released
            let startTime = CFAbsoluteTimeGetCurrent()
            while FileManager.default.fileExists(atPath: lockPath) {
                if CFAbsoluteTimeGetCurrent() - startTime > config.lockFileWaitTimeout {
                    // Lock timeout, proceed anyway (will likely fail)
                    break
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}

// MARK: - Errors

/// Error representing a failed Git operation after all retries
public struct GitOperationError: Error, LocalizedError, Sendable {
    public let command: String
    public let exitCode: Int32
    public let stderr: String
    public let attempts: Int

    public var errorDescription: String? {
        "Git command '\(command)' failed after \(attempts) attempt(s) " +
            "(exit code: \(exitCode)): \(stderr)"
    }
}

// MARK: - Global Convenience Functions

/// Execute a git command with standard retry behavior
public func git_retry(
    _ command: [String],
    cwd: String
) -> GitOperationRetryResult {
    let retry = GitOperationRetry(config: .standard)
    return retry.execute(gitCommand: command, cwd: cwd)
}

/// Execute git push with standard retry
public func git_push_retry(
    cwd: String,
    remote: String = "origin",
    branch: String? = nil
) -> GitOperationRetryResult {
    let retry = GitOperationRetry(config: .standard)
    return retry.push(cwd: cwd, remote: remote, branch: branch)
}

/// Execute git pull with standard retry
public func git_pull_retry(
    cwd: String,
    remote: String = "origin",
    branch: String? = nil
) -> GitOperationRetryResult {
    let retry = GitOperationRetry(config: .standard)
    return retry.pull(cwd: cwd, remote: remote, branch: branch)
}

/// Execute git fetch with standard retry
public func git_fetch_retry(
    cwd: String,
    remote: String? = nil
) -> GitOperationRetryResult {
    let retry = GitOperationRetry(config: .standard)
    return retry.fetch(cwd: cwd, remote: remote)
}
