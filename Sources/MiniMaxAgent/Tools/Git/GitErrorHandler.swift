import Foundation

/// Represents a parsed Git error with categorized type and context
public struct GitError: Error, LocalizedError, Sendable, Equatable {
    /// The category of the Git error
    public let category: Category

    /// The original stderr output
    public let rawMessage: String

    /// Exit code associated with this error
    public let exitCode: Int32

    /// The git command that was being executed
    public let command: String

    /// Suggested action to resolve the error
    public let suggestion: String?

    public enum Category: String, Sendable {
        // Authentication & Authorization
        case authenticationFailed = "AUTH_FAILED"
        case permissionDenied = "PERMISSION_DENIED"
        case notAuthenticated = "NOT_AUTHENTICATED"

        // Network
        case networkError = "NETWORK_ERROR"
        case remoteNotFound = "REMOTE_NOT_FOUND"
        case connectionTimeout = "CONNECTION_TIMEOUT"
        case sslError = "SSL_ERROR"

        // Merge & Conflict
        case mergeConflict = "MERGE_CONFLICT"
        case rebaseConflict = "REBASE_CONFLICT"
        case cherryPickConflict = "CHERRY_PICK_CONFLICT"
        case stashConflict = "STASH_CONFLICT"
        case conflictUnmerged = "CONFLICT_UNMERGED"
        case aborting = "ABORTING"

        // Reference errors
        case branchNotFound = "BRANCH_NOT_FOUND"
        case refNotFound = "REF_NOT_FOUND"
        case invalidRef = "INVALID_REF"
        case detachedHead = "DETACHED_HEAD"

        // Repository errors
        case notARepository = "NOT_A_REPOSITORY"
        case repositoryNotFound = "REPOSITORY_NOT_FOUND"
        case remoteAlreadyExists = "REMOTE_ALREADY_EXISTS"
        case branchAlreadyExists = "BRANCH_ALREADY_EXISTS"

        // Push/pull errors
        case pushRejected = "PUSH_REJECTED"
        case pushRejectedNonFastForward = "PUSH_REJECTED_NON_FAST_FORWARD"
        case pushRejectedUpdatesRejected = "PUSH_REJECTED_UPDATES_REJECTED"
        case pullWithStash = "PULL_WITH_STASH"

        // File errors
        case fileNotFound = "FILE_NOT_FOUND"
        case pathDoesNotExist = "PATH_DOES_NOT_EXIST"
        case cannotStageRemoved = "CANNOT_STAGE_REMOVED"
        case updateIndexFailed = "UPDATE_INDEX_FAILED"

        // Lock errors
        case lockFileExists = "LOCK_FILE_EXISTS"
        case lockFileBusy = "LOCK_FILE_BUSY"

        // Operation state
        case nothingToCommit = "NOTHING_TO_COMMIT"
        case nothingToPush = "NOTHING_TO_PUSH"
        case nothingToPull = "NOTHING_TO_PULL"
        case alreadyUpToDate = "ALREADY_UP_TO_DATE"

        // Rebase errors
        case nothingToRebase = "NOTHING_TO_REBASE"
        case rebaseNotPossible = "REBASE_NOT_POSSIBLE"
        case interactiveRebaseInProgress = "INTERACTIVE_REBASE_IN_PROGRESS"

        // Other
        case unknown = "UNKNOWN"
        case fatal = "FATAL"
    }

    public var errorDescription: String? {
        "\(category.rawValue): \(rawMessage)"
    }

    public init(
        category: Category,
        rawMessage: String,
        exitCode: Int32 = -1,
        command: String = "",
        suggestion: String? = nil
    ) {
        self.category = category
        self.rawMessage = rawMessage
        self.exitCode = exitCode
        self.command = command
        self.suggestion = suggestion
    }

    /// Check if this error indicates a merge/rebase conflict
    public var isConflict: Bool {
        switch category {
        case .mergeConflict, .rebaseConflict, .cherryPickConflict, .stashConflict, .conflictUnmerged:
            return true
        default:
            return false
        }
    }

    /// Check if this error indicates a transient failure that might succeed on retry
    public var isTransient: Bool {
        switch category {
        case .networkError, .connectionTimeout, .lockFileBusy:
            return true
        default:
            return false
        }
    }
}

/// Conflict information extracted from Git output
public struct GitConflictInfo: Sendable {
    /// The file paths involved in the conflict
    public let conflictedFiles: [String]

    /// Number of conflicted files
    public let conflictCount: Int

    /// Raw conflict markers from output
    public let rawConflictSections: [String]

    /// The operation that caused the conflict
    public let operationType: OperationType

    public enum OperationType: String, Sendable {
        case merge = "merge"
        case rebase = "rebase"
        case cherryPick = "cherry-pick"
        case revert = "revert"
        case pull = "pull"
        case stashPop = "stash pop"
        case unknown = "unknown"
    }

    public init(
        conflictedFiles: [String],
        conflictCount: Int,
        rawConflictSections: [String],
        operationType: OperationType
    ) {
        self.conflictedFiles = conflictedFiles
        self.conflictCount = conflictCount
        self.rawConflictSections = rawConflictSections
        self.operationType = operationType
    }
}

/// Result of parsing Git output (success or error)
public struct GitParseResult: Sendable {
    /// Whether the command succeeded
    public let success: Bool

    /// Parsed error if command failed
    public let error: GitError?

    /// Conflict info if conflicts were detected
    public let conflictInfo: GitConflictInfo?

    /// Raw stdout
    public let stdout: String

    /// Raw stderr
    public let stderr: String

    /// Exit code
    public let exitCode: Int32

    /// The command that was executed
    public let command: String

    public init(
        success: Bool,
        error: GitError? = nil,
        conflictInfo: GitConflictInfo? = nil,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        command: String
    ) {
        self.success = success
        self.error = error
        self.conflictInfo = conflictInfo
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.command = command
    }
}

/// GitErrorParser parses Git command output and categorizes errors
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Git error handling (parse stderr, detect conflicts)
///
/// Usage:
///   let parser = GitErrorParser()
///   let result = parser.parse(stdout: output, stderr: error, exitCode: code, command: "git merge")
///   if let error = result.error {
///       print("Git error: \(error.category)")
///       if let suggestion = error.suggestion {
///           print("Suggestion: \(suggestion)")
///       }
///   }
public struct GitErrorParser: Sendable {

    public init() {}

    // MARK: - Parse Git Output

    /// Parse Git command output and return categorized result
    public func parse(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        command: String
    ) -> GitParseResult {
        if exitCode == 0 {
            return GitParseResult(
                success: true,
                stdout: stdout,
                stderr: stderr,
                exitCode: exitCode,
                command: command
            )
        }

        // First check for conflicts
        let conflictInfo = detectConflicts(stdout: stdout, stderr: stderr, command: command)

        // Parse the error
        let error = parseError(stderr: stderr, stdout: stdout, exitCode: exitCode, command: command)

        return GitParseResult(
            success: false,
            error: error,
            conflictInfo: conflictInfo,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            command: command
        )
    }

    /// Parse stderr into a GitError
    public func parseError(
        stderr: String,
        stdout: String = "",
        exitCode: Int32,
        command: String
    ) -> GitError {
        let combined = stderr.isEmpty ? stdout : stderr
        let lowercased = combined.lowercased()

        // Detect error category
        let category = categorize(stderr: combined, stdout: stdout, exitCode: exitCode, command: command)

        // Generate suggestion based on category
        let suggestion = generateSuggestion(category: category, stderr: combined, command: command)

        return GitError(
            category: category,
            rawMessage: combined,
            exitCode: exitCode,
            command: command,
            suggestion: suggestion
        )
    }

    // MARK: - Conflict Detection

    /// Detect and parse conflict information from Git output
    public func detectConflicts(
        stdout: String,
        stderr: String,
        command: String
    ) -> GitConflictInfo? {
        let combined = stdout + "\n" + stderr
        let lowercased = combined.lowercased()

        // Check if this is a conflict situation
        let operationType = detectOperationType(command: command, stderr: lowercased)

        // Look for conflict markers
        let conflictMarkers = ["<<<<<<<", "=======", ">>>>>>>"]
        var rawSections: [String] = []
        var foundConflicts = false

        for marker in conflictMarkers {
            if combined.contains(marker) {
                foundConflicts = true
                break
            }
        }

        // Check for conflict-related error messages
        let hasConflictError = lowercased.contains("merge conflict") ||
            lowercased.contains("conflict") ||
            lowercased.contains("fix conflicts") ||
            lowercased.contains("both modified") ||
            lowercased.contains("both added") ||
            lowercased.contains("deleted by us") ||
            lowercased.contains("deleted by them")

        if !foundConflicts && !hasConflictError {
            return nil
        }

        // Extract conflicted file paths
        let conflictedFiles = extractConflictedFiles(from: combined)

        // Extract raw conflict sections
        rawSections = extractConflictSections(from: combined)

        return GitConflictInfo(
            conflictedFiles: conflictedFiles,
            conflictCount: conflictedFiles.count,
            rawConflictSections: rawSections,
            operationType: operationType
        )
    }

    // MARK: - Private Helpers

    private func categorize(
        stderr: String,
        stdout: String,
        exitCode: Int32,
        command: String
    ) -> GitError.Category {
        let lowercased = stderr.lowercased()

        // Authentication
        if lowercased.contains("authentication failed") ||
           lowercased.contains("could not authenticate") ||
           lowercased.contains("git: credential-") {
            return .authenticationFailed
        }

        if lowercased.contains("permission denied") || lowercased.contains("permission to") {
            return .permissionDenied
        }

        // Network
        if lowercased.contains("connection timed out") ||
           lowercased.contains("connection refused") ||
           lowercased.contains("network is unreachable") {
            return .connectionTimeout
        }

        if lowercased.contains("could not resolve host") ||
           lowercased.contains("could not read from remote") {
            return .networkError
        }

        if lowercased.contains("ssl") && (lowercased.contains("error") || lowercased.contains("certificate")) {
            return .sslError
        }

        if lowercased.contains("remote not found") || lowercased.contains("repository not found") {
            return .remoteNotFound
        }

        // Conflicts
        if lowercased.contains("merge conflict") || lowercased.contains("fix conflicts and then commit") {
            return .mergeConflict
        }

        if lowercased.contains("rebase conflict") || lowercased.contains("fix the conflicts and run") {
            if lowercased.contains("rebase") {
                return .rebaseConflict
            }
            return .mergeConflict
        }

        if lowercased.contains("cherry-pick conflict") {
            return .cherryPickConflict
        }

        if lowercased.contains("stash pop") && lowercased.contains("conflict") {
            return .stashConflict
        }

        if lowercased.contains("unmerged") || lowercased.contains("not possible because you have unmerged files") {
            return .conflictUnmerged
        }

        if lowercased.contains("abort") && lowercased.contains("rebase") {
            return .aborting
        }

        // Push/pull
        if lowercased.contains("push rejected") {
            if lowercased.contains("non-fast-forward") {
                return .pushRejectedNonFastForward
            }
            if lowercased.contains("updates were rejected") {
                return .pushRejectedUpdatesRejected
            }
            return .pushRejected
        }

        // Reference errors
        if lowercased.contains("branch not found") || lowercased.contains("no such branch") {
            return .branchNotFound
        }

        if lowercased.contains("ref not found") || lowercased.contains("no such ref") {
            return .refNotFound
        }

        if lowercased.contains("detached head") {
            return .detachedHead
        }

        // Repository errors
        if lowercased.contains("not a git repository") || lowercased.contains("fatal: not a git repository") {
            return .notARepository
        }

        if lowercased.contains("repository not found") {
            return .repositoryNotFound
        }

        if lowercased.contains("remote already exists") {
            return .remoteAlreadyExists
        }

        if lowercased.contains("branch already exists") || lowercased.contains("a branch named") {
            return .branchAlreadyExists
        }

        // Lock files
        if lowercased.contains("index.lock") || lowercased.contains("unable to lock") {
            return .lockFileExists
        }

        if lowercased.contains("could not lock") {
            return .lockFileBusy
        }

        // Nothing to do
        if lowercased.contains("nothing to commit") || lowercased.contains("nothing added to commit") {
            return .nothingToCommit
        }

        if lowercased.contains("everything up-to-date") || lowercased.contains("already up-to-date") {
            return .alreadyUpToDate
        }

        if lowercased.contains("nothing to push") || lowercased.contains("everything is up to date") {
            return .nothingToPush
        }

        if lowercased.contains("nothing to pull") {
            return .nothingToPull
        }

        // Rebase
        if lowercased.contains("nothing to rebase") || lowercased.contains("no changes in working tree") {
            return .nothingToRebase
        }

        if lowercased.contains("cannot rebase") || lowercased.contains("rebase not possible") {
            return .rebaseNotPossible
        }

        if lowercased.contains("interactive rebase is already in progress") {
            return .interactiveRebaseInProgress
        }

        // File errors
        if lowercased.contains("does not exist") || lowercased.contains("no such file") {
            return .fileNotFound
        }

        // Fatal error
        if lowercased.contains("fatal:") {
            return .fatal
        }

        return .unknown
    }

    private func generateSuggestion(
        category: GitError.Category,
        stderr: String,
        command: String
    ) -> String? {
        switch category {
        case .mergeConflict, .rebaseConflict, .cherryPickConflict, .stashConflict:
            return "Resolve conflicts manually, then stage and commit. Use 'git status' to see conflicting files."
        case .pushRejected, .pushRejectedNonFastForward:
            return "Fetch and merge/pull changes from remote before pushing, or use 'git push --force-with-lease'."
        case .pushRejectedUpdatesRejected:
            return "The remote has changes that conflict with your local changes. Pull and resolve conflicts first."
        case .lockFileExists, .lockFileBusy:
            return "Another Git operation is in progress. Wait or remove .git/index.lock if stale."
        case .authenticationFailed:
            return "Check your Git credentials. Use 'git config --global credential.helper' to manage credentials."
        case .permissionDenied:
            return "You may not have permission to push to this repository. Check your access rights."
        case .notAuthenticated:
            return "Authenticate with 'git push' using SSH key or HTTPS credentials."
        case .networkError, .connectionTimeout:
            return "Check your network connection. Retry the operation."
        case .remoteNotFound:
            return "Verify the remote URL is correct with 'git remote -v'."
        case .branchNotFound:
            return "Check available branches with 'git branch -a'."
        case .detachedHead:
            return "Create a branch with 'git checkout -b <branch-name>' to save your work."
        case .notARepository:
            return "Initialize a Git repository with 'git init' or navigate to a valid repository."
        case .nothingToCommit:
            return "No changes to commit. Use 'git status' to see current state."
        case .alreadyUpToDate:
            return "Your branch is already up to date with the remote."
        case .rebaseNotPossible:
            return "Resolve conflicts before continuing the rebase."
        case .interactiveRebaseInProgress:
            return "Complete or abort the current interactive rebase before starting a new one."
        case .fatal:
            // Extract the fatal message
            if let range = stderr.lowercased().range(of: "fatal:") {
                let message = String(stderr[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return message
            }
            return "Review the error message and correct the issue."
        default:
            return nil
        }
    }

    private func detectOperationType(command: String, stderr: String) -> GitConflictInfo.OperationType {
        let lowercased = command.lowercased()

        if lowercased.contains("merge") {
            return .merge
        }
        if lowercased.contains("rebase") {
            return .rebase
        }
        if lowercased.contains("cherry-pick") {
            return .cherryPick
        }
        if lowercased.contains("revert") {
            return .revert
        }
        if lowercased.contains("pull") {
            return .pull
        }
        if lowercased.contains("stash pop") || lowercased.contains("stash pop") {
            return .stashPop
        }

        return .unknown
    }

    private func extractConflictedFiles(from output: String) -> [String] {
        var files: [String] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Both modified/deleted/added: path
            if trimmed.hasPrefix("both modified:") || trimmed.hasPrefix("both added:") {
                let file = String(trimmed.dropFirst(trimmed.contains("both modified:") ? 14 : 11)).trimmingCharacters(in: .whitespaces)
                if !file.isEmpty {
                    files.append(file)
                }
            }

            // Deleted by us/them: path
            if trimmed.hasPrefix("deleted by us:") || trimmed.hasPrefix("deleted by them:") {
                let file = String(trimmed.dropFirst(trimmed.hasPrefix("deleted by us:") ? 14 : 15)).trimmingCharacters(in: .whitespaces)
                if !file.isEmpty {
                    files.append(file)
                }
            }

            // Unmerged: path
            if trimmed.hasPrefix("unmerged:") || trimmed.hasPrefix("both modified:") {
                let parts = trimmed.components(separatedBy: "unmerged:").last ?? trimmed.components(separatedBy: "both modified:").last ?? ""
                let file = parts.trimmingCharacters(in: .whitespaces)
                if !file.isEmpty && !files.contains(file) {
                    files.append(file)
                }
            }
        }

        // Also extract from conflict markers
        let markerLines = output.components(separatedBy: .newlines).filter { line in
            line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>")
        }

        return files
    }

    private func extractConflictSections(from output: String) -> [String] {
        var sections: [String] = []
        var currentSection = ""
        var inConflict = false

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("<<<<<<<") {
                inConflict = true
                currentSection = line + "\n"
            } else if line.hasPrefix("=======") {
                currentSection += line + "\n"
            } else if line.hasPrefix(">>>>>>>") {
                currentSection += line + "\n"
                sections.append(currentSection)
                currentSection = ""
                inConflict = false
            } else if inConflict {
                currentSection += line + "\n"
            }
        }

        return sections
    }
}

// MARK: - Convenience Extensions

extension GitErrorParser {

    /// Parse git status output for errors
    public func parseStatus(stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: "", stderr: stderr, exitCode: exitCode, command: "git status")
    }

    /// Parse git diff output for errors
    public func parseDiff(stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: "", stderr: stderr, exitCode: exitCode, command: "git diff")
    }

    /// Parse git log output for errors
    public func parseLog(stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: "", stderr: stderr, exitCode: exitCode, command: "git log")
    }

    /// Parse git push output for errors
    public func parsePush(stdout: String, stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: stdout, stderr: stderr, exitCode: exitCode, command: "git push")
    }

    /// Parse git pull output for errors (checks for conflicts)
    public func parsePull(stdout: String, stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: stdout, stderr: stderr, exitCode: exitCode, command: "git pull")
    }

    /// Parse git merge output for errors (checks for conflicts)
    public func parseMerge(stdout: String, stderr: String, exitCode: Int32) -> GitParseResult {
        parse(stdout: stdout, stderr: stderr, exitCode: exitCode, command: "git merge")
    }
}
