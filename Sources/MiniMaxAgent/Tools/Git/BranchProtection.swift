import Foundation

/// Represents a branch protection rule
public struct BranchProtectionRule: Sendable, Equatable {
    public let branchName: String
    public let isProtected: Bool
    public let requiresPr: Bool
    public let requiresStatusChecks: Bool
    public let requiresCodeOwnerApproval: Bool
    public let blocksForcePush: Bool
    public let blocksDeletion: Bool
    public let requiresCommitSigning: Bool

    public init(
        branchName: String,
        isProtected: Bool,
        requiresPr: Bool = true,
        requiresStatusChecks: Bool = false,
        requiresCodeOwnerApproval: Bool = false,
        blocksForcePush: Bool = true,
        blocksDeletion: Bool = true,
        requiresCommitSigning: Bool = false
    ) {
        self.branchName = branchName
        self.isProtected = isProtected
        self.requiresPr = requiresPr
        self.requiresStatusChecks = requiresStatusChecks
        self.requiresCodeOwnerApproval = requiresCodeOwnerApproval
        self.blocksForcePush = blocksForcePush
        self.blocksDeletion = blocksDeletion
        self.requiresCommitSigning = requiresCommitSigning
    }

    /// Default protected branch patterns
    public static let protectedPatterns: [String] = [
        "^main$",
        "^master$",
        "^develop$",
        "^staging$",
        "^production$",
        "^release/.*$",
        "^hotfix/.*$"
    ]
}

/// Result of a branch protection check
public struct BranchProtectionCheckResult: Sendable {
    public let branchName: String
    public let isAllowed: Bool
    public let reason: String
    public let suggestedAction: String?

    public init(branchName: String, isAllowed: Bool, reason: String, suggestedAction: String? = nil) {
        self.branchName = branchName
        self.isAllowed = isAllowed
        self.reason = reason
        self.suggestedAction = suggestedAction
    }
}

/// Branch protection awareness for Git operations
///
/// Detects whether branches are protected and suggests appropriate actions
/// for operations like push, force-push, and branch deletion.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Branch protection awareness
///
/// Usage:
///   let checker = BranchProtectionChecker()
///   let result = checker.checkPush(branch: "main")
///   if !result.isAllowed {
///       print("Cannot push: \(result.reason)")
///   }
public struct BranchProtectionChecker: Sendable {

    /// Default protected branch name patterns (regex)
    public let protectedPatterns: [String]

    /// Custom protected branches (exact names)
    public let protectedBranchNames: Set<String>

    /// Block force push on protected branches (default: true)
    public let blockForcePush: Bool

    /// Block deletion of protected branches (default: true)
    public let blockDeletion: Bool

    public init(
        protectedPatterns: [String] = BranchProtectionRule.protectedPatterns,
        protectedBranchNames: Set<String> = [],
        blockForcePush: Bool = true,
        blockDeletion: Bool = true
    ) {
        self.protectedPatterns = protectedPatterns
        self.protectedBranchNames = protectedBranchNames
        self.blockForcePush = blockForcePush
        self.blockDeletion = blockDeletion
    }

    // MARK: - Public API

    /// Check if a branch is protected
    public func isProtected(_ branchName: String) -> Bool {
        // Check exact match first
        if protectedBranchNames.contains(branchName) {
            return true
        }

        // Check pattern matches
        for pattern in protectedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(branchName.startIndex..<branchName.endIndex, in: branchName)
                if regex.firstMatch(in: branchName, options: [], range: range) != nil {
                    return true
                }
            }
        }

        return false
    }

    /// Check if push is allowed to a branch
    public func checkPush(branch: String, force: Bool = false) -> BranchProtectionCheckResult {
        if !isProtected(branch) {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: true,
                reason: "Branch '\(branch)' is not protected"
            )
        }

        if force && blockForcePush {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: false,
                reason: "Force push is blocked on protected branch '\(branch)'",
                suggestedAction: "Create a feature branch, make changes, and open a pull request instead"
            )
        }

        return BranchProtectionCheckResult(
            branchName: branch,
            isAllowed: true,
            reason: "Push to protected branch '\(branch)' requires a pull request",
            suggestedAction: "Consider creating a feature branch for your changes"
        )
    }

    /// Check if branch deletion is allowed
    public func checkDelete(branch: String) -> BranchProtectionCheckResult {
        if !isProtected(branch) {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: true,
                reason: "Branch '\(branch)' is not protected"
            )
        }

        if blockDeletion {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: false,
                reason: "Deletion of protected branch '\(branch)' is blocked",
                suggestedAction: "Protected branches cannot be deleted directly"
            )
        }

        return BranchProtectionCheckResult(
            branchName: branch,
            isAllowed: true,
            reason: "Deletion of protected branch '\(branch)' requires explicit confirmation"
        )
    }

    /// Check if rebasing is allowed on a branch
    public func checkRebase(branch: String, interactive: Bool = false) -> BranchProtectionCheckResult {
        if !isProtected(branch) {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: true,
                reason: "Branch '\(branch)' is not protected"
            )
        }

        if interactive {
            return BranchProtectionCheckResult(
                branchName: branch,
                isAllowed: false,
                reason: "Interactive rebase is blocked on protected branch '\(branch)'",
                suggestedAction: "Perform the rebase on a feature branch, then merge via PR"
            )
        }

        return BranchProtectionCheckResult(
            branchName: branch,
            isAllowed: true,
            reason: "Rebase on protected branch '\(branch)' should be avoided",
            suggestedAction: "Prefer merge over rebase for protected branches to preserve history"
        )
    }

    /// Get protection info for a branch
    public func getProtectionInfo(branch: String) -> BranchProtectionRule {
        let protected = isProtected(branch)
        return BranchProtectionRule(
            branchName: branch,
            isProtected: protected,
            requiresPr: protected,
            requiresStatusChecks: protected,
            requiresCodeOwnerApproval: false,
            blocksForcePush: protected && blockForcePush,
            blocksDeletion: protected && blockDeletion
        )
    }

    /// List all protected branches from a list
    public func filterProtected(_ branches: [String]) -> [String] {
        branches.filter { isProtected($0) }
    }

    /// Get a human-readable summary of protection status
    public func summary(for branch: String) -> String {
        if !isProtected(branch) {
            return "Branch '\(branch)' is not protected. Direct pushes and force-push are allowed."
        }

        var details: [String] = []
        details.append("Branch '\(branch)' is protected")
        details.append("• Requires pull request: \(requiresPr(for: branch))")
        details.append("• Blocks force push: \(blocksForcePush(for: branch))")
        details.append("• Blocks deletion: \(blocksDeletion(for: branch))")

        return details.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func requiresPr(for branch: String) -> String {
        isProtected(branch) ? "yes" : "no"
    }

    private func blocksForcePush(for branch: String) -> String {
        (isProtected(branch) && blockForcePush) ? "yes" : "no"
    }

    private func blocksDeletion(for branch: String) -> String {
        (isProtected(branch) && blockDeletion) ? "yes" : "no"
    }
}

/// Git command executor for branch protection awareness
/// Provides actual Git integration using command-line git
public struct GitBranchProtection: Sendable {

    public enum GitError: Error, LocalizedError, Sendable {
        case notARepository
        case commandFailed(String)
        case branchNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .notARepository:
                return "Not a Git repository"
            case .commandFailed(let message):
                return "Git command failed: \(message)"
            case .branchNotFound(let branch):
                return "Branch not found: \(branch)"
            }
        }
    }

    public let checker: BranchProtectionChecker
    public let workingDirectory: String

    public init(
        workingDirectory: String,
        protectedPatterns: [String] = BranchProtectionRule.protectedPatterns,
        protectedBranchNames: Set<String> = []
    ) {
        self.workingDirectory = workingDirectory
        self.checker = BranchProtectionChecker(
            protectedPatterns: protectedPatterns,
            protectedBranchNames: protectedBranchNames
        )
    }

    /// Get current branch name
    public func currentBranch() throws -> String {
        let result = try runGitCommand(["rev-parse", "--abbrev-ref", "HEAD"])
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if current branch is protected
    public func isCurrentBranchProtected() throws -> Bool {
        let branch = try currentBranch()
        return checker.isProtected(branch)
    }

    /// Check protection before push (accepts optional remote/branch from git)
    public func checkPrePush(remote: String? = nil, branch: String? = nil) throws -> BranchProtectionCheckResult {
        // Determine the branch being pushed
        let targetBranch: String
        if let branch = branch {
            targetBranch = branch
        } else {
            targetBranch = try currentBranch()
        }

        // Detect force push from reflog or pre-push hook data
        // For now, we check without force unless specified
        return checker.checkPush(branch: targetBranch, force: false)
    }

    /// Run a git command and return output
    private func runGitCommand(_ arguments: [String]) throws -> String {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            throw GitError.commandFailed("Failed to execute git: \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if task.terminationStatus != 0 && output.contains("fatal") {
            throw GitError.commandFailed(output)
        }

        return output
    }
}

// MARK: - Swift CLI Helper

extension BranchProtectionChecker {

    /// Create a checker from environment (HOME/.gitprotection or repo-specific)
    public static func fromEnvironment() -> BranchProtectionChecker {
        // Default implementation - could be extended to read from config files
        BranchProtectionChecker()
    }
}
