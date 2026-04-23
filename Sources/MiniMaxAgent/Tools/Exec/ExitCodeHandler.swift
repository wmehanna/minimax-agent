import Foundation

/// Error representing a non-zero exit code from a command
public struct ExitCodeError: Error, LocalizedError, Sendable, Equatable {
    /// The command that was executed
    public let command: String

    /// The working directory
    public let workingDirectory: String

    /// The actual exit code
    public let exitCode: Int32

    /// Standard error output (if available)
    public let stderr: String

    /// Human-readable description
    public var errorDescription: String? {
        if stderr.isEmpty {
            return "Command '\(command)' exited with code \(exitCode) (working directory: \(workingDirectory))"
        }
        return "Command '\(command)' exited with code \(exitCode): \(stderr) (working directory: \(workingDirectory))"
    }

    public init(command: String, workingDirectory: String, exitCode: Int32, stderr: String = "") {
        self.command = command
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

/// Exit code categories for common error types
public enum ExitCodeCategory: Int32, Sendable {
    /// Success (exit code 0)
    case success = 0

    /// General error (exit code 1)
    case generalError = 1

    /// Misuse of shell command (exit code 2)
    case misuse = 2

    /// Cannot execute (exit code 126)
    case cannotExecute = 126

    /// Command not found (exit code 127)
    case commandNotFound = 127

    /// Invalid exit argument (exit code 128)
    case invalidExit = 128

    /// Signal exit codes (128 + signal number, e.g., 137 for SIGKILL)
    case signalBase = 129

    public var description: String {
        switch self {
        case .success:
            return "Success"
        case .generalError:
            return "General error"
        case .misuse:
            return "Shell command misuse"
        case .cannotExecute:
            return "Cannot execute permission problem"
        case .commandNotFound:
            return "Command not found"
        case .invalidExit:
            return "Invalid exit argument"
        case .signalBase:
            return "Signal termination"
        }
    }

    /// Determine category from exit code
    public static func from(_ code: Int32) -> ExitCodeCategory {
        switch code {
        case 0:
            return .success
        case 1:
            return .generalError
        case 2:
            return .misuse
        case 126:
            return .cannotExecute
        case 127:
            return .commandNotFound
        case 128:
            return .invalidExit
        default:
            if code > 128 {
                return .signalBase
            }
            return .generalError
        }
    }
}

/// Validation result for exit code checks
public struct ExitCodeValidation: Sendable, Equatable {
    /// Whether the validation passed
    public let valid: Bool

    /// The exit code that was validated
    public let exitCode: Int32

    /// Category of the exit code
    public let category: ExitCodeCategory

    /// Error if validation failed
    public let error: ExitCodeError?

    /// Warnings (non-fatal issues)
    public let warnings: [String]

    public init(
        valid: Bool,
        exitCode: Int32,
        category: ExitCodeCategory,
        error: ExitCodeError? = nil,
        warnings: [String] = []
    ) {
        self.valid = valid
        self.exitCode = exitCode
        self.category = category
        self.error = error
        self.warnings = warnings
    }

    /// Successful validation
    public static func success(exitCode: Int32, warnings: [String] = []) -> ExitCodeValidation {
        ExitCodeValidation(
            valid: true,
            exitCode: exitCode,
            category: ExitCodeCategory.from(exitCode),
            error: nil,
            warnings: warnings
        )
    }

    /// Failed validation
    public static func failure(exitCode: Int32, error: ExitCodeError) -> ExitCodeValidation {
        ExitCodeValidation(
            valid: false,
            exitCode: exitCode,
            category: ExitCodeCategory.from(exitCode),
            error: error,
            warnings: []
        )
    }
}

/// Configuration for exit code validation
public struct ExitCodeValidatorConfig: Sendable {
    /// Expected exit codes (any code not in this list is considered an error)
    /// If empty, only non-zero codes are errors
    public let expectedCodes: Set<Int32>

    /// Treat specific exit codes as warnings instead of errors
    public let warningCodes: Set<Int32>

    /// Treat exit code 0 as success (default: true)
    public let requireZeroForSuccess: Bool

    /// Include stderr in error details
    public let includeStderr: Bool

    public init(
        expectedCodes: Set<Int32> = [],
        warningCodes: Set<Int32> = [],
        requireZeroForSuccess: Bool = true,
        includeStderr: Bool = true
    ) {
        self.expectedCodes = expectedCodes
        self.warningCodes = warningCodes
        self.requireZeroForSuccess = requireZeroForSuccess
        self.includeStderr = includeStderr
    }

    /// Default configuration - zero is success, anything else is an error
    public static let standard = ExitCodeValidatorConfig()

    /// Lenient configuration - allows any exit code as long as it's expected or not a signal
    public static let lenient = ExitCodeValidatorConfig(
        warningCodes: Set<Int32>([1, 2, 126, 127, 128, 129, 130, 131, 137, 143, 255])
    )

    /// Strict configuration - only exit code 0 is success
    public static let strict = ExitCodeValidatorConfig(requireZeroForSuccess: true)
}

/// ExitCodeValidator validates exit codes and propagates errors
///
/// Validates exit codes from command execution, determines error categories,
/// and provides error propagation for failed commands.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Exit code validation and error propagation
///
/// Usage:
///   let validator = ExitCodeValidator(config: .standard)
///   let result = validator.validate(command: "ls", exitCode: 0)
///   if !result.valid {
///       throw result.error!
///   }
///
/// Or use the static convenience:
///   try ExitCodeError.raiseIfNeeded(exitCode: 1, command: "make", cwd: "/project")
public struct ExitCodeValidator: Sendable {

    public let config: ExitCodeValidatorConfig

    public init(config: ExitCodeValidatorConfig = .standard) {
        self.config = config
    }

    // MARK: - Validate Exit Code

    /// Validate an exit code
    /// - Parameters:
    ///   - exitCode: The exit code to validate
    ///   - command: The command that was executed
    ///   - cwd: Working directory
    ///   - stderr: Standard error output (for error details)
    /// - Returns: ExitCodeValidation result
    public func validate(
        exitCode: Int32,
        command: String,
        cwd: String,
        stderr: String = ""
    ) -> ExitCodeValidation {
        // Check if exit code is in the warning list
        if config.warningCodes.contains(exitCode) {
            return ExitCodeValidation(
                valid: true,
                exitCode: exitCode,
                category: ExitCodeCategory.from(exitCode),
                error: nil,
                warnings: ["Exit code \(exitCode) (\(ExitCodeCategory.from(exitCode).description)) - \(command)"]
            )
        }

        // Check expected codes
        if !config.expectedCodes.isEmpty {
            if config.expectedCodes.contains(exitCode) {
                return .success(exitCode: exitCode)
            } else {
                let error = ExitCodeError(
                    command: command,
                    workingDirectory: cwd,
                    exitCode: exitCode,
                    stderr: config.includeStderr ? stderr : ""
                )
                return .failure(exitCode: exitCode, error: error)
            }
        }

        // Default: zero is success, non-zero is error
        if exitCode == 0 {
            return .success(exitCode: exitCode)
        }

        let error = ExitCodeError(
            command: command,
            workingDirectory: cwd,
            exitCode: exitCode,
            stderr: config.includeStderr ? stderr : ""
        )
        return .failure(exitCode: exitCode, error: error)
    }

    /// Validate a CommandResult
    /// - Parameter result: The command result to validate
    /// - Returns: ExitCodeValidation result
    public func validate(_ result: CommandResult) -> ExitCodeValidation {
        validate(
            exitCode: result.exitCode,
            command: result.command,
            cwd: result.workingDirectory,
            stderr: result.stderr
        )
    }

    // MARK: - Throwing Helpers

    /// Throw an error if the exit code is non-zero
    /// - Parameters:
    ///   - exitCode: The exit code to check
    ///   - command: The command that was executed
    ///   - cwd: Working directory
    ///   - stderr: Standard error output
    public static func raiseIfNeeded(
        exitCode: Int32,
        command: String,
        cwd: String,
        stderr: String = ""
    ) throws {
        if exitCode != 0 {
            throw ExitCodeError(
                command: command,
                workingDirectory: cwd,
                exitCode: exitCode,
                stderr: stderr
            )
        }
    }

    /// Throw an error if the CommandResult indicates failure
    /// - Parameter result: The command result to check
    public static func raiseIfNeeded(_ result: CommandResult) throws {
        try raiseIfNeeded(
            exitCode: result.exitCode,
            command: result.command,
            cwd: result.workingDirectory,
            stderr: result.stderr
        )
    }

    /// Validate and throw if invalid
    /// - Parameters:
    ///   - exitCode: The exit code to validate
    ///   - command: The command that was executed
    ///   - cwd: Working directory
    ///   - stderr: Standard error output
    public static func validateOrThrow(
        exitCode: Int32,
        command: String,
        cwd: String,
        stderr: String = ""
    ) throws -> ExitCodeValidation {
        let validator = ExitCodeValidator()
        let validation = validator.validate(exitCode: exitCode, command: command, cwd: cwd, stderr: stderr)
        if !validation.valid, let error = validation.error {
            throw error
        }
        return validation
    }
}

// MARK: - Error Propagation Helpers

extension ExitCodeValidator {

    /// Wrap a command result in a Result type with proper error propagation
    /// - Parameter result: The command result to wrap
    /// - Returns: Result with either the CommandResult or an ExitCodeError
    public func toResult(_ result: CommandResult) -> Result<CommandResult, ExitCodeError> {
        let validation = validate(result)
        if validation.valid {
            return .success(result)
        } else {
            return .failure(validation.error!)
        }
    }

    /// Convert to throwing function
    /// - Parameter result: The command result to convert
    /// - Returns: The same CommandResult if successful
    /// - Throws: ExitCodeError if the command failed
    public func asThrowing(_ result: CommandResult) throws -> CommandResult {
        let validation = validate(result)
        if !validation.valid {
            throw validation.error!
        }
        return result
    }
}

// MARK: - Global Helpers

/// Global function to check if an exit code represents success
/// - Parameter exitCode: The exit code to check
/// - Returns: true if exit code is 0
public func isSuccessfulExitCode(_ exitCode: Int32) -> Bool {
    exitCode == 0
}

/// Get a description of an exit code
/// - Parameter exitCode: The exit code to describe
/// - Returns: Human-readable description
public func describeExitCode(_ exitCode: Int32) -> String {
    let category = ExitCodeCategory.from(exitCode)
    switch category {
    case .success:
        return "Success (exit code 0)"
    case .signalBase:
        let signal = exitCode - 128
        return "Terminated by signal \(signal)"
    default:
        return "Exit code \(exitCode): \(category.description)"
    }
}
