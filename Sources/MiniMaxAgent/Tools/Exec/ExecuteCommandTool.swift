import Foundation

/// Represents the result of a shell command execution
public struct CommandResult: Sendable, Equatable {
    /// The command that was executed
    public let command: String

    /// The working directory where the command was executed
    public let workingDirectory: String

    /// Exit code returned by the process (0 typically means success)
    public let exitCode: Int32

    /// Standard output from the command
    public let stdout: String

    /// Standard error output from the command
    public let stderr: String

    /// Whether the command succeeded (exit code 0)
    public var success: Bool { exitCode == 0 }

    /// Execution time in milliseconds
    public let durationMs: Int64

    /// Human-readable description of the result
    public var summary: String {
        """
        Command: \(command)
        Working Directory: \(workingDirectory)
        Exit Code: \(exitCode)
        Duration: \(durationMs)ms
        Success: \(success)
        """
    }

    public init(
        command: String,
        workingDirectory: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
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

/// Options for command execution
public struct ExecuteCommandOptions: Sendable {
    /// Environment variables to set (merged with current environment)
    public let environment: [String: String]

    /// Whether to merge stderr into stdout (default: false)
    public let mergeStderr: Bool

    /// Timeout in seconds (0 = no timeout)
    public let timeoutSeconds: Int

    /// User to run the command as (if nil, runs as current user)
    public let user: String?

    /// Current working directory for the subprocess (defaults to cwd parameter)
    public let cwd: String?

    public init(
        environment: [String: String] = [:],
        mergeStderr: Bool = false,
        timeoutSeconds: Int = 0,
        user: String? = nil,
        cwd: String? = nil
    ) {
        self.environment = environment
        self.mergeStderr = mergeStderr
        self.timeoutSeconds = timeoutSeconds
        self.user = user
        self.cwd = cwd
    }

    /// Default options (no timeout, separate stderr)
    public static let `default` = ExecuteCommandOptions()
}

/// Execute command tool for running shell commands
///
/// Executes a shell command in a specified working directory and returns
/// the result including exit code, stdout, stderr, and execution time.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: execute_command(cmd: String, cwd: String) -> CommandResult
///
/// Usage:
///   let tool = ExecuteCommandTool()
///   let result = tool.execute(command: "ls -la", cwd: "/path/to/project")
///   if result.success {
///       print(result.stdout)
///   } else {
///       print("Error: \(result.stderr)")
///   }
///
/// Or use the static convenience method:
///   let result = ExecuteCommandTool.execute(command: "pwd", cwd: "/tmp")
public struct ExecuteCommandTool: Sendable {

    public let options: ExecuteCommandOptions

    public init(options: ExecuteCommandOptions = .default) {
        self.options = options
    }

    // MARK: - Public API

    /// Execute a shell command in the specified working directory
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - cwd: The working directory to execute the command in
    /// - Returns: CommandResult containing exit code, stdout, stderr, and duration
    public func execute(command: String, cwd: String) -> CommandResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Determine working directory
        let workingDir = options.cwd ?? cwd

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in options.environment {
            env[key] = value
        }
        process.environment = env

        process.standardOutput = stdoutPipe
        process.standardError = options.mergeStderr ? stdoutPipe : stderrPipe

        var stdoutData = Data()
        var stderrData = Data()

        // Handle stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutData.append(data)
            }
        }

        // Handle stderr (only if not merged)
        if !options.mergeStderr {
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrData.append(data)
                }
            }
        }

        do {
            try process.run()
        } catch {
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = Int64((endTime - startTime) * 1000)
            return CommandResult(
                command: command,
                workingDirectory: workingDir,
                exitCode: -1,
                stdout: "",
                stderr: "Failed to start process: \(error.localizedDescription)",
                durationMs: durationMs
            )
        }

        // Handle timeout
        if options.timeoutSeconds > 0 {
            var timeoutOccurred = false
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + .seconds(options.timeoutSeconds))
            if result == .timedOut {
                timeoutOccurred = true
                process.terminate()
            }

            if timeoutOccurred {
                let endTime = CFAbsoluteTimeGetCurrent()
                let durationMs = Int64((endTime - startTime) * 1000)
                return CommandResult(
                    command: command,
                    workingDirectory: workingDir,
                    exitCode: -1,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: "Command timed out after \(options.timeoutSeconds) seconds",
                    durationMs: durationMs
                )
            }
        } else {
            process.waitUntilExit()
        }

        // Read remaining data
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if !options.mergeStderr {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }

        // Get final output
        let finalStdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let finalStderr = String(data: stderrData, encoding: .utf8) ?? ""

        let endTime = CFAbsoluteTimeGetCurrent()
        let durationMs = Int64((endTime - startTime) * 1000)

        return CommandResult(
            command: command,
            workingDirectory: workingDir,
            exitCode: process.terminationStatus,
            stdout: finalStdout,
            stderr: finalStderr,
            durationMs: durationMs
        )
    }

    /// Static convenience method for simple command execution
    public static func execute(command: String, cwd: String) -> CommandResult {
        ExecuteCommandTool().execute(command: command, cwd: cwd)
    }
}

// MARK: - Convenience Extensions

extension ExecuteCommandTool {

    /// Execute with timeout
    public func executeWithTimeout(command: String, cwd: String, timeoutSeconds: Int) -> CommandResult {
        let opts = ExecuteCommandOptions(
            environment: options.environment,
            mergeStderr: options.mergeStderr,
            timeoutSeconds: timeoutSeconds,
            user: options.user,
            cwd: options.cwd
        )
        return ExecuteCommandTool(options: opts).execute(command: command, cwd: cwd)
    }

    /// Execute with merged stderr into stdout
    public func executeMerged(command: String, cwd: String) -> CommandResult {
        let opts = ExecuteCommandOptions(
            environment: options.environment,
            mergeStderr: true,
            timeoutSeconds: options.timeoutSeconds,
            user: options.user,
            cwd: options.cwd
        )
        return ExecuteCommandTool(options: opts).execute(command: command, cwd: cwd)
    }

    /// Execute with additional environment variables
    public func executeWithEnv(command: String, cwd: String, env: [String: String]) -> CommandResult {
        let opts = ExecuteCommandOptions(
            environment: env,
            mergeStderr: options.mergeStderr,
            timeoutSeconds: options.timeoutSeconds,
            user: options.user,
            cwd: options.cwd
        )
        return ExecuteCommandTool(options: opts).execute(command: command, cwd: cwd)
    }
}

// MARK: - Global Function

/// Global function for executing commands (matches task signature)
/// - Parameters:
///   - cmd: The shell command to execute
///   - cwd: The working directory to execute the command in
/// - Returns: CommandResult containing exit code, stdout, stderr, and duration
public func execute_command(cmd: String, cwd: String) -> CommandResult {
    ExecuteCommandTool.execute(command: cmd, cwd: cwd)
}
