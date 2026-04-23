import Foundation

/// Represents a dangerous command pattern
public struct DangerousPattern: Sendable, Equatable {
    /// Name/identifier of the dangerous pattern
    public let name: String

    /// The pattern to match (can be regex or literal)
    public let pattern: String

    /// Whether this is a regex pattern
    public let isRegex: Bool

    /// Reason why this is dangerous
    public let reason: String

    /// Severity level
    public let severity: Severity

    /// Category of danger
    public let category: Category

    public enum Severity: String, Sendable, Comparable {
        case low = "LOW"
        case medium = "MEDIUM"
        case high = "HIGH"
        case critical = "CRITICAL"

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.low, .medium, .high, .critical]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    public enum Category: String, Sendable {
        case fileDeletion = "FILE_DELETION"
        case systemModification = "SYSTEM_MODIFICATION"
        case networkAccess = "NETWORK_ACCESS"
        case credentialAccess = "CREDENTIAL_ACCESS"
        case privilegeEscalation = "PRIVILEGE_ESCALATION"
        case dataExfiltration = "DATA_EXFILTRATION"
        case destructiveOperation = "DESTRUCTIVE_OPERATION"
        case remoteCodeExecution = "REMOTE_CODE_EXECUTION"
    }

    public init(
        name: String,
        pattern: String,
        isRegex: Bool = false,
        reason: String,
        severity: Severity,
        category: Category
    ) {
        self.name = name
        self.pattern = pattern
        self.isRegex = isRegex
        self.reason = reason
        self.severity = severity
        self.category = category
    }
}

/// Result of dangerous command detection
public struct DangerousCommandResult: Sendable {
    /// Whether the command is considered dangerous
    public let isDangerous: Bool

    /// All detected dangerous patterns
    public let detectedPatterns: [DangerousPattern]

    /// Highest severity among detected patterns
    public let maxSeverity: DangerousPattern.Severity?

    /// Whether the command should be blocked
    public let shouldBlock: Bool

    /// Detailed warnings for each detected pattern
    public let warnings: [String]

    public init(
        isDangerous: Bool,
        detectedPatterns: [DangerousPattern] = [],
        maxSeverity: DangerousPattern.Severity? = nil,
        shouldBlock: Bool = false,
        warnings: [String] = []
    ) {
        self.isDangerous = isDangerous
        self.detectedPatterns = detectedPatterns
        self.maxSeverity = maxSeverity
        self.shouldBlock = shouldBlock
        self.warnings = warnings
    }
}

/// DangerousCommandDetector identifies potentially dangerous shell commands
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: Dangerous command detection and blocking
///
/// Usage:
///   let detector = DangerousCommandDetector()
///   let result = detector.analyze("rm -rf /")
///   if result.shouldBlock {
///       print("Dangerous command blocked!")
///   }
public struct DangerousCommandDetector: Sendable {

    /// Default dangerous patterns for system commands
    public static let defaultPatterns: [DangerousPattern] = [
        // Critical file deletion
        DangerousPattern(
            name: "recursive_force_delete_root",
            pattern: #"rm\s+-rf\s+/(?:\s+[a-zA-Z0-9_/.-]*)*"#,
            isRegex: true,
            reason: "Recursive force delete from root can delete entire filesystem",
            severity: .critical,
            category: .fileDeletion
        ),
        DangerousPattern(
            name: "recursive_delete_etc",
            pattern: #"rm\s+-rf\s+/etc"#,
            isRegex: true,
            reason: "Deleting /etc would destroy system configuration",
            severity: .critical,
            category: .fileDeletion
        ),
        DangerousPattern(
            name: "recursive_delete_var",
            pattern: #"rm\s+-rf\s+/var"#,
            isRegex: true,
            reason: "Deleting /var would destroy system data and logs",
            severity: .critical,
            category: .fileDeletion
        ),
        DangerousPattern(
            name: "recursive_delete_usr",
            pattern: #"rm\s+-rf\s+/usr"#,
            isRegex: true,
            reason: "Deleting /usr would destroy system binaries",
            severity: .critical,
            category: .fileDeletion
        ),
        DangerousPattern(
            name: "delete_ssh_keys",
            pattern: #"rm\s+.*\.ssh\/"#,
            isRegex: true,
            reason: "Deleting .ssh directory would remove authentication credentials",
            severity: .high,
            category: .credentialAccess
        ),

        // System modification
        DangerousPattern(
            name: "disk_format",
            pattern: #"(?i)mkfs\s+"#,
            isRegex: true,
            reason: "Formatting a disk destroys all data on it",
            severity: .critical,
            category: .destructiveOperation
        ),
        DangerousPattern(
            name: "dd_to_disk",
            pattern: #"dd\s+.*of=/dev/"#,
            isRegex: true,
            reason: "Direct disk writing can destroy entire disk contents",
            severity: .critical,
            category: .destructiveOperation
        ),
        DangerousPattern(
            name: "modify_cron",
            pattern: #"(?i)crontab\s+-r"#,
            isRegex: true,
            reason: "Removing crontab would delete all scheduled jobs",
            severity: .high,
            category: .systemModification
        ),
        DangerousPattern(
            name: "systemctl_stop_critical",
            pattern: #"(?i)systemctl\s+(stop|disable)\s+(firewalld|sshd|cron)"#,
            isRegex: true,
            reason: "Stopping critical system services can leave system in unusable state",
            severity: .high,
            category: .systemModification
        ),

        // Network access
        DangerousPattern(
            name: "curl_to_unknown_host",
            pattern: #"curl\s+.*\s+--output\s+/dev"#,
            isRegex: true,
            reason: "Downloading to /dev could be data exfiltration",
            severity: .medium,
            category: .networkAccess
        ),
        DangerousPattern(
            name: "wget_unknown_url",
            pattern: #"wget\s+.*\s+-O\s+/dev"#,
            isRegex: true,
            reason: "Downloading to /dev could be data exfiltration",
            severity: .medium,
            category: .networkAccess
        ),
        DangerousPattern(
            name: "netcat_listener",
            pattern: #"nc\s+-l\s+-p\s+\d+"#,
            isRegex: true,
            reason: "Netcat listener could be used for reverse shells",
            severity: .high,
            category: .remoteCodeExecution
        ),
        DangerousPattern(
            name: "bash_reverse_shell",
            pattern: #"(?i)bash\s+-i\s+.*&\s*/dev/tcp/"#,
            isRegex: true,
            reason: "Reverse shell allows unauthorized remote access",
            severity: .critical,
            category: .remoteCodeExecution
        ),
        DangerousPattern(
            name: "curl_pipe_to_bash",
            pattern: #"curl\s+.*\|\s*(?:bash|sh|zsh)"#,
            isRegex: true,
            reason: "Piping downloaded content to shell is extremely dangerous",
            severity: .critical,
            category: .remoteCodeExecution
        ),
        DangerousPattern(
            name: "wget_pipe_to_bash",
            pattern: #"wget\s+.*\|\s*(?:bash|sh|zsh)"#,
            isRegex: true,
            reason: "Piping downloaded content to shell is extremely dangerous",
            severity: .critical,
            category: .remoteCodeExecution
        ),

        // Credential access
        DangerousPattern(
            name: "read_shadow_file",
            pattern: #"(?i)cat\s+/etc/shadow"#,
            isRegex: true,
            reason: "Reading /etc/shadow exposes password hashes",
            severity: .critical,
            category: .credentialAccess
        ),
        DangerousPattern(
            name: "sudo_su",
            pattern: #"sudo\s+su"#,
            isRegex: true,
            reason: "Escalating to root without explicit command",
            severity: .medium,
            category: .privilegeEscalation
        ),
        DangerousPattern(
            name: "chmod_777",
            pattern: #"chmod\s+777\s+"#,
            isRegex: true,
            reason: "World-writable permissions are a security risk",
            severity: .medium,
            category: .systemModification
        ),
        DangerousPattern(
            name: "chmod_suid",
            pattern: #"chmod\s+[47]\d{3}\s+"#,
            isRegex: true,
            reason: "Setting SUID bit can be used for privilege escalation",
            severity: .high,
            category: .privilegeEscalation
        ),

        // Data exfiltration
        DangerousPattern(
            name: "tar_archive_etc",
            pattern: #"tar\s+.*czf\s+.*\s+/etc"#,
            isRegex: true,
            reason: "Archiving /etc could be data exfiltration",
            severity: .high,
            category: .dataExfiltration
        ),
        DangerousPattern(
            name: "scp_to_unknown",
            pattern: #"scp\s+.*(?<!known_hosts):\/"#,
            isRegex: true,
            reason: "Copying files to unknown hosts could be data exfiltration",
            severity: .high,
            category: .dataExfiltration
        ),

        // Destructive operations
        DangerousPattern(
            name: "fork_bomb",
            pattern: #":\(\)\{\s*:\|:\s*&\s*\}\s*;:"#,
            isRegex: true,
            reason: "Fork bomb can crash the system",
            severity: .critical,
            category: .destructiveOperation
        ),
        DangerousPattern(
            name: "dd_zero_disk",
            pattern: #"dd\s+.*if=/dev/zero\s+.*of=/dev/"#,
            isRegex: true,
            reason: "Writing zeros to block device destroys data",
            severity: .critical,
            category: .destructiveOperation
        ),
        DangerousPattern(
            name: "shutdown_abrupt",
            pattern: #"(?i)shutdown\s+-h\s+now"#,
            isRegex: true,
            reason: "Abrupt shutdown can cause data loss",
            severity: .low,
            category: .destructiveOperation
        ),
        DangerousPattern(
            name: "reboot_force",
            pattern: #"(?i)reboot\s+-f"#,
            isRegex: true,
            reason: "Force reboot can cause data loss",
            severity: .medium,
            category: .destructiveOperation
        )
    ]

    /// Custom patterns beyond defaults
    public let customPatterns: [DangerousPattern]

    /// Block threshold (commands at or above this severity will be blocked)
    public let blockThreshold: DangerousPattern.Severity

    /// Whether to enable blocking
    public let blockingEnabled: Bool

    public init(
        customPatterns: [DangerousPattern] = [],
        blockThreshold: DangerousPattern.Severity = .critical,
        blockingEnabled: Bool = true
    ) {
        self.customPatterns = customPatterns
        self.blockThreshold = blockThreshold
        self.blockingEnabled = blockingEnabled
    }

    // MARK: - Public API

    /// Analyze a command for dangerous patterns
    /// - Parameters:
    ///   - command: The command string to analyze
    ///   - context: Optional context (e.g., working directory)
    /// - Returns: DangerousCommandResult with analysis
    public func analyze(_ command: String, context: String? = nil) -> DangerousCommandResult {
        let allPatterns = Self.defaultPatterns + customPatterns
        var detected: [DangerousPattern] = []

        for pattern in allPatterns {
            if matches(pattern: pattern, in: command) {
                detected.append(pattern)
            }
        }

        if detected.isEmpty {
            return DangerousCommandResult(
                isDangerous: false
            )
        }

        let maxSeverity = detected.map(\.severity).max()
        let shouldBlock = blockingEnabled && (maxSeverity ?? .low) >= blockThreshold

        let warnings = detected.map { pattern in
            "[\(pattern.severity.rawValue)] \(pattern.name): \(pattern.reason)"
        }

        return DangerousCommandResult(
            isDangerous: true,
            detectedPatterns: detected,
            maxSeverity: maxSeverity,
            shouldBlock: shouldBlock,
            warnings: warnings
        )
    }

    /// Quick check if command is dangerous
    /// - Parameter command: The command to check
    /// - Returns: true if dangerous
    public func isDangerous(_ command: String) -> Bool {
        analyze(command).isDangerous
    }

    /// Quick check if command should be blocked
    /// - Parameter command: The command to check
    /// - Returns: true if should be blocked
    public func shouldBlock(_ command: String) -> Bool {
        analyze(command).shouldBlock
    }

    /// Get all patterns that match a command
    /// - Parameter command: The command to check
    /// - Returns: Array of matching patterns
    public func matchingPatterns(for command: String) -> [DangerousPattern] {
        let allPatterns = Self.defaultPatterns + customPatterns
        return allPatterns.filter { matches(pattern: $0, in: command) }
    }

    /// Get all patterns in a category
    /// - Parameter category: The category to filter by
    /// - Returns: Array of patterns in that category
    public func patterns(in category: DangerousPattern.Category) -> [DangerousPattern] {
        let allPatterns = Self.defaultPatterns + customPatterns
        return allPatterns.filter { $0.category == category }
    }

    /// Get all patterns at or above a severity
    /// - Parameter severity: Minimum severity
    /// - Returns: Array of patterns at or above that severity
    public func patterns(atOrAbove severity: DangerousPattern.Severity) -> [DangerousPattern] {
        let allPatterns = Self.defaultPatterns + customPatterns
        return allPatterns.filter { $0.severity >= severity }
    }

    // MARK: - Private Helpers

    private func matches(pattern: DangerousPattern, in command: String) -> Bool {
        if pattern.isRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(command.startIndex..<command.endIndex, in: command)
            return regex.firstMatch(in: command, options: [], range: range) != nil
        } else {
            return command.contains(pattern.pattern)
        }
    }
}

// MARK: - Command Blocker Extension

/// Extension that integrates dangerous command detection into command execution
extension DangerousCommandDetector {

    /// Block result when a dangerous command is detected
    public struct BlockedCommandError: Error, LocalizedError, Sendable {
        public let command: String
        public let detectionResult: DangerousCommandResult

        public var errorDescription: String? {
            "Command blocked due to dangerous patterns detected:\n" +
                detectionResult.warnings.joined(separator: "\n")
        }
    }

    /// Validate and optionally block a command before execution
    /// - Parameters:
    ///   - command: The command to validate
    ///   - context: Optional context
    /// - Throws: BlockedCommandError if command should be blocked
    /// - Returns: The detection result if not blocked
    public func validateOrBlock(_ command: String, context: String? = nil) throws -> DangerousCommandResult {
        let result = analyze(command, context: context)
        if result.shouldBlock {
            throw BlockedCommandError(command: command, detectionResult: result)
        }
        return result
    }

    /// Safe wrapper for command that throws if dangerous
    /// - Parameters:
    ///   - command: The command to execute
    ///   - context: Optional context
    /// - Throws: BlockedCommandError if dangerous and blocking is enabled
    /// - Returns: true if safe to execute
    public func assertSafe(_ command: String, context: String? = nil) throws {
        _ = try validateOrBlock(command, context: context)
    }
}

// MARK: - Global Convenience

/// Check if a command contains dangerous patterns
public func is_dangerous_command(_ command: String) -> Bool {
    DangerousCommandDetector().isDangerous(command)
}

/// Check if a command should be blocked
public func should_block_command(_ command: String) -> Bool {
    DangerousCommandDetector().shouldBlock(command)
}

/// Analyze a command for dangerous patterns
public func analyze_command(_ command: String) -> DangerousCommandResult {
    DangerousCommandDetector().analyze(command)
}
