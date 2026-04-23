import Foundation

/// Result of a Git operation
public struct GitCommandResult: Sendable {
    /// Whether the operation succeeded
    public let success: Bool

    /// Command output (stdout)
    public let output: String

    /// Error output (stderr)
    public let errorOutput: String

    /// Exit code
    public let exitCode: Int32

    /// The command that was executed
    public let command: String

    /// Working directory
    public let workingDirectory: String

    /// Parsed error if available
    public let error: GitError?

    /// Conflict info if conflicts were detected
    public let conflictInfo: GitConflictInfo?

    /// Execution duration
    public let durationMs: Int64

    public init(
        success: Bool,
        output: String = "",
        errorOutput: String = "",
        exitCode: Int32 = 0,
        command: String = "",
        workingDirectory: String = "",
        error: GitError? = nil,
        conflictInfo: GitConflictInfo? = nil,
        durationMs: Int64 = 0
    ) {
        self.success = success
        self.output = output
        self.errorOutput = errorOutput
        self.exitCode = exitCode
        self.command = command
        self.workingDirectory = workingDirectory
        self.error = error
        self.conflictInfo = conflictInfo
        self.durationMs = durationMs
    }

    public var isSuccess: Bool { success }
    public var isConflict: Bool { conflictInfo != nil }
}

/// GitCommands provides a comprehensive interface for Git operations
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: git clone, status, diff, commit, push, pull, fetch, rebase, merge
///
/// Usage:
///   let git = GitCommands(cwd: "/path/to/repo")
///   let status = git.status()
///   let result = git.commit(message: "Fix bug")
public struct GitCommands: Sendable {

    /// Working directory for Git operations
    public let cwd: String

    /// Error parser for Git output
    public let errorParser: GitErrorParser

    /// Branch protection checker
    public let branchProtection: GitBranchProtection

    /// Retry handler for transient failures
    public let retryHandler: GitOperationRetry?

    public init(
        cwd: String,
        checkBranchProtection: Bool = true,
        retryOnTransientFailure: Bool = false
    ) {
        self.cwd = cwd
        self.errorParser = GitErrorParser()
        self.branchProtection = GitBranchProtection(workingDirectory: cwd)
        self.retryHandler = retryOnTransientFailure ? GitOperationRetry(config: .standard) : nil
    }

    // MARK: - Repository Operations

    /// Clone a repository
    /// - Parameters:
    ///   - url: The repository URL to clone
    ///   - branch: Optional branch to clone (defaults to default branch)
    /// - Returns: GitCommandResult
    public func clone(url: String, branch: String? = nil) -> GitCommandResult {
        var args = ["clone"]
        if let branch = branch {
            args.append(contentsOf: ["--branch", branch])
        }
        args.append(url)
        args.append(cwd)

        return executeGit(args)
    }

    /// Initialize a new Git repository
    /// - Parameter bare: Whether to create a bare repository
    /// - Returns: GitCommandResult
    public func initRepository(bare: Bool = false) -> GitCommandResult {
        var args = ["init"]
        if bare {
            args.append("--bare")
        }
        args.append(cwd)
        return executeGit(args)
    }

    // MARK: - Status & Info

    /// Get repository status
    /// - Returns: GitCommandResult with status output
    public func status() -> GitCommandResult {
        executeGit(["status"])
    }

    /// Get short status format
    /// - Returns: GitCommandResult with short status
    public func statusShort() -> GitCommandResult {
        executeGit(["status", "--short", "-b"])
    }

    /// Get the current branch name
    /// - Returns: The branch name or nil if detached HEAD
    public func currentBranch() -> String? {
        let result = executeGit(["rev-parse", "--abbrev-ref", "HEAD"])
        if result.success {
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Check if repository is clean (no uncommitted changes)
    /// - Returns: true if clean
    public func isClean() -> Bool {
        let result = statusShort()
        // Short format: empty or only "## HEAD" line means clean
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.success && (trimmed.isEmpty || trimmed == "## HEAD")
    }

    /// Get list of remotes
    /// - Returns: GitCommandResult with remote list
    public func remoteList() -> GitCommandResult {
        executeGit(["remote", "-v"])
    }

    // MARK: - Diff Operations

    /// Show working tree diff
    /// - Returns: GitCommandResult with diff
    public func diff() -> GitCommandResult {
        executeGit(["diff"])
    }

    /// Show diff against staged changes
    /// - Returns: GitCommandResult with staged diff
    public func diffStaged() -> GitCommandResult {
        executeGit(["diff", "--cached"])
    }

    /// Diff against a specific commit/branch
    /// - Parameter target: Commit hash or branch name
    /// - Returns: GitCommandResult with diff
    public func diffAgainst(_ target: String) -> GitCommandResult {
        executeGit(["diff", target])
    }

    /// Diff between two commits/branches
    /// - Parameters:
    ///   - from: Source commit/branch
    ///   - to: Target commit/branch
    /// - Returns: GitCommandResult with diff
    public func diffRange(from: String, to: String) -> GitCommandResult {
        executeGit(["diff", from, to])
    }

    /// Show changes in a commit
    /// - Parameter commit: Commit hash
    /// - Returns: GitCommandResult with commit changes
    public func show(_ commit: String) -> GitCommandResult {
        executeGit(["show", commit])
    }

    // MARK: - Staging & Committing

    /// Stage files for commit
    /// - Parameter files: File paths to stage (empty means all)
    /// - Returns: GitCommandResult
    public func add(_ files: [String] = []) -> GitCommandResult {
        var args = ["add"]
        if files.isEmpty {
            args.append(".")
        } else {
            args.append(contentsOf: files)
        }
        return executeGit(args)
    }

    /// Create a commit
    /// - Parameters:
    ///   - message: Commit message
    ///   - author: Optional author override (format: "Name <email>")
    /// - Returns: GitCommandResult with commit info
    public func commit(message: String, author: String? = nil) -> GitCommandResult {
        var args = ["commit", "-m", message]
        if let author = author {
            args.append(contentsOf: ["--author", author])
        }
        return executeGit(args)
    }

    /// Amend the last commit
    /// - Parameters:
    ///   - message: New commit message (nil to keep original)
    ///   - author: New author (nil to keep original)
    /// - Returns: GitCommandResult
    public func amend(message: String? = nil, author: String? = nil) -> GitCommandResult {
        var args = ["commit", "--amend", "--no-edit"]
        if let message = message {
            args = ["commit", "--amend", "-m", message]
        }
        if let author = author {
            args.append(contentsOf: ["--author", author])
        }
        return executeGit(args)
    }

    /// Get commit log
    /// - Parameters:
    ///   - limit: Max number of commits (default 10)
    ///   - format: Log format string
    /// - Returns: GitCommandResult with log
    public func log(limit: Int = 10, format: String = "%H|%s|%an|%ad") -> GitCommandResult {
        executeGit(["log", "--format=\(format)", "-n", "\(limit)"])
    }

    // MARK: - Branch Operations

    /// List branches
    /// - Parameters:
    ///   - all: Include remote branches
    ///   - current: Show current branch
    /// - Returns: GitCommandResult with branch list
    public func branchList(all: Bool = false, current: Bool = false) -> GitCommandResult {
        var args = ["branch"]
        if all {
            args.append("-a")
        }
        if current {
            args.append("--show-current")
        }
        return executeGit(args)
    }

    /// Create a new branch
    /// - Parameters:
    ///   - name: Branch name
    ///   - startPoint: Optional commit/branch to start from
    /// - Returns: GitCommandResult
    public func branchCreate(name: String, startPoint: String? = nil) -> GitCommandResult {
        var args = ["branch", name]
        if let startPoint = startPoint {
            args.append(startPoint)
        }
        return executeGit(args)
    }

    /// Delete a branch
    /// - Parameters:
    ///   - name: Branch name
    ///   - force: Force delete
    /// - Returns: GitCommandResult
    public func branchDelete(name: String, force: Bool = false) -> GitCommandResult {
        var args = ["branch", force ? "-D" : "-d", name]
        return executeGit(args)
    }

    /// Switch to a branch
    /// - Parameter name: Branch name
    /// - Returns: GitCommandResult
    public func checkout(_ name: String) -> GitCommandResult {
        executeGit(["checkout", name])
    }

    /// Create and switch to a new branch
    /// - Parameter name: Branch name
    /// - Returns: GitCommandResult
    public func checkoutNewBranch(_ name: String) -> GitCommandResult {
        executeGit(["checkout", "-b", name])
    }

    // MARK: - Remote Operations

    /// Fetch from remote
    /// - Parameters:
    ///   - remote: Remote name (default: all)
    ///   - branch: Specific branch to fetch
    /// - Returns: GitCommandResult
    public func fetch(remote: String? = nil, branch: String? = nil) -> GitCommandResult {
        var args = ["fetch"]
        if let remote = remote {
            args.append(remote)
            if let branch = branch {
                args.append(branch)
            }
        }
        return executeGitWithRetry(args)
    }

    /// Pull from remote
    /// - Parameters:
    ///   - remote: Remote name
    ///   - branch: Branch name
    /// - Returns: GitCommandResult
    public func pull(remote: String? = nil, branch: String? = nil) -> GitCommandResult {
        var args = ["pull"]
        if let remote = remote {
            args.append(remote)
            if let branch = branch {
                args.append(branch)
            }
        }
        return executeGitWithRetry(args)
    }

    /// Push to remote
    /// - Parameters:
    ///   - remote: Remote name
    ///   - branch: Branch name
    ///   - force: Force push
    /// - Returns: GitCommandResult
    public func push(remote: String = "origin", branch: String? = nil, force: Bool = false) -> GitCommandResult {
        // Check branch protection
        if let currentBranch = currentBranch() {
            let protection = branchProtection.checker.checkPush(branch: currentBranch, force: force)
            if !protection.isAllowed {
                return GitCommandResult(
                    success: false,
                    errorOutput: protection.reason,
                    exitCode: 1,
                    command: "git push",
                    workingDirectory: cwd,
                    error: GitError(
                        category: .permissionDenied,
                        rawMessage: protection.reason,
                        command: "git push"
                    )
                )
            }
        }

        var args = ["push"]
        if force {
            args.append("--force-with-lease")
        }
        args.append(remote)
        if let branch = branch {
            args.append(branch)
        }
        return executeGitWithRetry(args)
    }

    // MARK: - Merge & Rebase

    /// Merge a branch
    /// - Parameters:
    ///   - branch: Branch to merge
    ///   - noFF: Create merge commit even for fast-forward
    /// - Returns: GitCommandResult
    public func merge(branch: String, noFF: Bool = false) -> GitCommandResult {
        var args = ["merge"]
        if noFF {
            args.append("--no-ff")
        }
        args.append(branch)
        return executeGit(args)
    }

    /// Rebase onto a branch
    /// - Parameters:
    ///   - branch: Branch to rebase onto
    ///   - interactive: Interactive rebase
    /// - Returns: GitCommandResult
    public func rebase(branch: String, interactive: Bool = false) -> GitCommandResult {
        var args = ["rebase"]
        if interactive {
            args.append("-i")
        }
        args.append(branch)
        return executeGit(args)
    }

    /// Abort a rebase or merge
    /// - Returns: GitCommandResult
    public func abort() -> GitCommandResult {
        executeGit(["merge", "--abort"])
    }

    /// Continue a rebase
    /// - Returns: GitCommandResult
    public func rebaseContinue() -> GitCommandResult {
        executeGit(["rebase", "--continue"])
    }

    // MARK: - Stash

    /// Stash changes
    /// - Parameters:
    ///   - includeUntracked: Include untracked files
    ///   - message: Stash message
    /// - Returns: GitCommandResult
    public func stash(includeUntracked: Bool = false, message: String? = nil) -> GitCommandResult {
        var args = ["stash"]
        if includeUntracked {
            args.append("-u")
        }
        if let message = message {
            args.append(contentsOf: ["push", "-m", message])
        } else {
            args.append("push")
        }
        return executeGit(args)
    }

    /// Pop stash
    /// - Parameter stashRef: Stash reference (default: most recent)
    /// - Returns: GitCommandResult
    public func stashPop(stashRef: String = "stash@{0}") -> GitCommandResult {
        executeGit(["stash", "pop", stashRef])
    }

    /// List stashes
    /// - Returns: GitCommandResult with stash list
    public func stashList() -> GitCommandResult {
        executeGit(["stash", "list"])
    }

    // MARK: - Private Helpers

    func executeGit(_ args: [String]) -> GitCommandResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let command = "git " + args.joined(separator: " ")

        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = 0

        do {
            try task.run()
            task.waitUntilExit()
            exitCode = task.terminationStatus
        } catch {
            stderr = "Failed to execute git: \(error.localizedDescription)"
            exitCode = -1
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        stdout = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        stderr = String(data: errorData, encoding: .utf8) ?? ""

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Parse error and conflict info
        let parseResult = errorParser.parse(stdout: stdout, stderr: stderr, exitCode: exitCode, command: command)

        return GitCommandResult(
            success: exitCode == 0,
            output: stdout,
            errorOutput: stderr,
            exitCode: exitCode,
            command: command,
            workingDirectory: cwd,
            error: parseResult.error,
            conflictInfo: parseResult.conflictInfo,
            durationMs: Int64(duration * 1000)
        )
    }

    private func executeGitWithRetry(_ args: [String]) -> GitCommandResult {
        if let retry = retryHandler {
            let retryResult = retry.execute(gitCommand: args, cwd: cwd)
            return GitCommandResult(
                success: retryResult.succeeded,
                output: retryResult.output,
                errorOutput: retryResult.errorOutput,
                exitCode: retryResult.exitCode,
                command: retryResult.command,
                workingDirectory: cwd,
                durationMs: Int64(retryResult.totalDuration * 1000)
            )
        }
        return executeGit(args)
    }
}

// MARK: - Convenience Global Functions

/// Execute a git command in a directory
public func git_command(
    _ args: [String],
    cwd: String
) -> GitCommandResult {
    let git = GitCommands(cwd: cwd)
    return git.executeGit(args)
}

/// Quick git status
public func git_status(cwd: String) -> GitCommandResult {
    GitCommands(cwd: cwd).status()
}

/// Quick git log
public func git_log(cwd: String, limit: Int = 10) -> GitCommandResult {
    GitCommands(cwd: cwd).log(limit: limit)
}

/// Quick git diff
public func git_diff(cwd: String) -> GitCommandResult {
    GitCommands(cwd: cwd).diff()
}

/// Quick git diff against staging
public func git_diff_staged(cwd: String) -> GitCommandResult {
    GitCommands(cwd: cwd).diffStaged()
}
