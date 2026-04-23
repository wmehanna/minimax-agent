import Foundation

/// Commit message validation result
public struct CommitMessageValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [CommitMessageError]
    public let warnings: [CommitMessageWarning]

    public init(isValid: Bool, errors: [CommitMessageError] = [], warnings: [CommitMessageWarning] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// Detailed validation errors that block commit
public struct CommitMessageError: Sendable, Equatable {
    public let code: ErrorCode
    public let message: String
    public let range: Range<String.Index>?

    public enum ErrorCode: String, Sendable {
        case emptyMessage = "EMPTY_MESSAGE"
        case tooShort = "TOO_SHORT"
        case subjectTooLong = "SUBJECT_TOO_LONG"
        case subjectCapitalized = "SUBJECT_CAPITALIZED"
        case subjectEndsWithPeriod = "SUBJECT_ENDS_WITH_PERIOD"
        case bodyLineTooLong = "BODY_LINE_TOO_LONG"
        case missingBreakLine = "MISSING_BREAK_LINE"
        case multipleBlankLines = "MULTIPLE_BLANK_LINES"
        case trailingWhitespace = "TRAILING_WHITESPACE"
        case invalidFormat = "INVALID_FORMAT"
        case containsForbiddenPatterns = "FORBIDDEN_PATTERNS"
    }

    public init(code: ErrorCode, message: String, range: Range<String.Index>? = nil) {
        self.code = code
        self.message = message
        self.range = range
    }
}

/// Non-blocking warnings
public struct CommitMessageWarning: Sendable, Equatable {
    public let code: WarningCode
    public let message: String

    public enum WarningCode: String, Sendable {
        case missingBody = "MISSING_BODY"
        case bodyEndsPoorly = "BODY_ENDS_POORLY"
        case imperativeMood = "IMPERATIVE_MOOD"
        case missingIssueReference = "MISSING_ISSUE_REFERENCE"
    }

    public init(code: WarningCode, message: String) {
        self.code = code
        self.message = message
    }
}

/// Conventional commit types
public enum CommitType: String, CaseIterable, Sendable {
    case feat
    case fix
    case docs
    case style
    case refactor
    case perf
    case test
    case build
    case ci
    case chore
    case revert
    case merge

    public var description: String {
        switch self {
        case .feat: return "A new feature"
        case .fix: return "A bug fix"
        case .docs: return "Documentation only changes"
        case .style: return "Code style changes (formatting, semicolons, etc)"
        case .refactor: return "Code refactoring without changing functionality"
        case .perf: return "Performance improvements"
        case .test: return "Adding or correcting tests"
        case .build: return "Build system or external dependencies"
        case .ci: return "CI configuration changes"
        case .chore: return "Other changes that don't modify src or test files"
        case .revert: return "Reverts a previous commit"
        case .merge: return "Merge branch or pull request"
        }
    }
}

/// Scope constraint for validation
public struct ScopeConstraint: Sendable {
    public let allowedScopes: Set<String>?
    public let maxLength: Int

    public init(allowedScopes: Set<String>? = nil, maxLength: Int = 30) {
        self.allowedScopes = allowedScopes
        self.maxLength = maxLength
    }
}

/// Validation configuration
public struct CommitMessageValidatorConfig: Sendable {
    public let maxSubjectLength: Int
    public let maxBodyLineLength: Int
    public let requireConventionalFormat: Bool
    public let requireScope: Bool
    public let requireBreakLine: Bool
    public let scopeConstraint: ScopeConstraint?
    public let forbiddenPatterns: [String]
    public let allowedTypes: Set<CommitType>

    public static let conventional = CommitMessageValidatorConfig(
        maxSubjectLength: 50,
        maxBodyLineLength: 72,
        requireConventionalFormat: true,
        requireScope: false,
        requireBreakLine: true,
        scopeConstraint: nil,
        forbiddenPatterns: ["DEBUG:", "XXX:", "HACK:", "FIXME:"],
        allowedTypes: Set(CommitType.allCases)
    )

    public static let strict = CommitMessageValidatorConfig(
        maxSubjectLength: 50,
        maxBodyLineLength: 72,
        requireConventionalFormat: true,
        requireScope: true,
        requireBreakLine: true,
        scopeConstraint: ScopeConstraint(maxLength: 20),
        forbiddenPatterns: ["DEBUG:", "XXX:", "HACK:", "FIXME:", "WIP:"],
        allowedTypes: Set(CommitType.allCases)
    )

    public init(
        maxSubjectLength: Int = 50,
        maxBodyLineLength: Int = 72,
        requireConventionalFormat: Bool = true,
        requireScope: Bool = false,
        requireBreakLine: Bool = true,
        scopeConstraint: ScopeConstraint? = nil,
        forbiddenPatterns: [String] = [],
        allowedTypes: Set<CommitType>? = nil
    ) {
        self.maxSubjectLength = maxSubjectLength
        self.maxBodyLineLength = maxBodyLineLength
        self.requireConventionalFormat = requireConventionalFormat
        self.requireScope = requireScope
        self.requireBreakLine = requireBreakLine
        self.scopeConstraint = scopeConstraint
        self.forbiddenPatterns = forbiddenPatterns
        self.allowedTypes = allowedTypes ?? Set(CommitType.allCases)
    }
}

/**
 * CommitMessageValidator — validates commit messages against Conventional Commits
 * and configurable project standards.
 *
 * Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
 * Task: Commit message validation
 *
 * Usage:
 *   let validator = CommitMessageValidator(config: .conventional)
 *   let result = validator.validate("feat(auth): add login via OAuth")
 */
public struct CommitMessageValidator: Sendable {

    /// Default config (Conventional Commits specification)
    public static let `default` = CommitMessageValidator(config: .conventional)

    public let config: CommitMessageValidatorConfig

    public init(config: CommitMessageValidatorConfig = .conventional) {
        self.config = config
    }

    // MARK: - Public API

    /// Validate a commit message string
    public func validate(_ message: String) -> CommitMessageValidationResult {
        var errors: [CommitMessageError] = []
        var warnings: [CommitMessageWarning] = []

        let trimmed = message.trimmingCharacters(in: .newlines)

        // 1. Empty check
        if trimmed.isEmpty {
            return CommitMessageValidationResult(
                isValid: false,
                errors: [CommitMessageError(code: .emptyMessage, message: "Commit message cannot be empty")],
                warnings: []
            )
        }

        let lines = trimmed.components(separatedBy: .newlines)

        // 2. Subject + body separation
        let subjectLine = lines[0]
        let bodyLines = lines.count > 1 ? Array(lines.dropFirst()) : []

        // 3. Subject validations
        errors.append(contentsOf: validateSubject(subjectLine))

        // 4. Body validations (if present)
        if !bodyLines.isEmpty {
            errors.append(contentsOf: validateBody(bodyLines))
        } else {
            // Warn if body is missing but subject is long or references issues
            if subjectLine.count > config.maxSubjectLength {
                warnings.append(CommitMessageWarning(
                    code: .missingBody,
                    message: "Long subject but no body. Consider adding a body explaining the change."
                ))
            }
        }

        // 5. Conventional format validation
        if config.requireConventionalFormat {
            let conventionalErrors = validateConventionalFormat(subjectLine)
            errors.append(contentsOf: conventionalErrors)
        }

        // 6. Forbidden patterns
        let forbiddenErrors = validateForbiddenPatterns(trimmed)
        errors.append(contentsOf: forbiddenErrors)

        // 7. Warnings
        warnings.append(contentsOf: generateWarnings(subjectLine: subjectLine, bodyLines: bodyLines))

        return CommitMessageValidationResult(
            isValid: errors.isEmpty,
            errors: deduplicateErrors(errors),
            warnings: warnings
        )
    }

    /// Quick boolean check
    public func isValid(_ message: String) -> Bool {
        validate(message).isValid
    }

    /// Validate from git commit object fields
    public func validate(subject: String, body: String?) -> CommitMessageValidationResult {
        let fullMessage = body.map { "\(subject)\n\($0)" } ?? subject
        return validate(fullMessage)
    }

    // MARK: - Subject Validation

    private func validateSubject(_ subject: String) -> [CommitMessageError] {
        var errors: [CommitMessageError] = []

        // Length check
        if subject.count > config.maxSubjectLength {
            errors.append(CommitMessageError(
                code: .subjectTooLong,
                message: "Subject line exceeds \(config.maxSubjectLength) characters (currently \(subject.count)). "
                    + "Move extended description to the body.",
                range: subject.startIndex..<subject.index(subject.startIndex, offsetBy: config.maxSubjectLength)
            ))
        }

        // Capitalization check (first letter)
        if let first = subject.first, first.isLetter {
            let normalized = String(first)
            if normalized != normalized.uppercased() && subject.hasPrefix(subject.lowercased().prefix(1) + "") {
                // Only flag if it starts with lowercase but has other capitals (mixed case)
                // Allow all-lowercase (some teams prefer this)
            }
            // Conventional Commits requires lowercase after type: but the type itself is lowercase
        }

        // First character should not be capitalized for conventional commits (lowercase type)
        if config.requireConventionalFormat {
            if let first = subject.first, first.isUppercase {
                let typePrefix = subject.components(separatedBy: "(").first ?? subject
                let typePart = typePrefix.components(separatedBy: ":").first ?? ""
                if CommitType(rawValue: typePart.lowercased()) != nil {
                    errors.append(CommitMessageError(
                        code: .subjectCapitalized,
                        message: "Subject should not start with a capital letter. "
                            + "After the type (e.g., 'feat:'), start with lowercase."
                    ))
                }
            }
        }

        // Ends with period
        if subject.hasSuffix(".") && !subject.hasSuffix("...") {
            // Allow "..." but not single "." at end
            if subject.last == "." {
                errors.append(CommitMessageError(
                    code: .subjectEndsWithPeriod,
                    message: "Subject should not end with a period. Keep it concise."
                ))
            }
        }

        return errors
    }

    // MARK: - Body Validation

    private func validateBody(_ lines: [String]) -> [CommitMessageError] {
        var errors: [CommitMessageError] = []

        for (index, line) in lines.enumerated() {
            // Trailing whitespace
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                errors.append(CommitMessageError(
                    code: .trailingWhitespace,
                    message: "Line \(index + 2) has trailing whitespace.",
                    range: nil
                ))
            }

            // Line length
            if line.count > config.maxBodyLineLength {
                errors.append(CommitMessageError(
                    code: .bodyLineTooLong,
                    message: "Body line \(index + 2) exceeds \(config.maxBodyLineLength) characters (currently \(line.count)).",
                    range: nil
                ))
            }

            // Multiple blank lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        errors.append(CommitMessageError(
                            code: .multipleBlankLines,
                            message: "Multiple consecutive blank lines found at line \(index + 2). Use a single blank line only.",
                            range: nil
                        ))
                    }
                }
            }
        }

        return errors
    }

    // MARK: - Conventional Format Validation

    private func validateConventionalFormat(_ subject: String) -> [CommitMessageError] {
        var errors: [CommitMessageError] = []

        // Pattern: type(scope)?: description
        // or: type(scope)!: description for breaking changes

        let pattern = "^(\\w+)(\\([^)]+\\))?(!)?:\\s+.+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return errors
        }

        let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
        let matches = regex.matches(in: subject, options: [], range: range)

        if matches.isEmpty {
            errors.append(CommitMessageError(
                code: .invalidFormat,
                message: "Subject does not match Conventional Commits format: "
                    + "'<type>(<scope>)?: <description>'. "
                    + "Example: 'feat(auth): add OAuth login'",
                range: nil
            ))
            return errors
        }

        // Validate type
        if let typeMatch = matches.first {
            let typeRange = Range(typeMatch.range(at: 1), in: subject)!
            let type = String(subject[typeRange]).lowercased()

            if let commitType = CommitType(rawValue: type) {
                if !config.allowedTypes.contains(commitType) {
                    errors.append(CommitMessageError(
                        code: .invalidFormat,
                        message: "Invalid commit type '\(type)'. "
                            + "Allowed types: \(config.allowedTypes.map { $0.rawValue }.sorted().joined(separator: ", "))",
                        range: typeRange
                    ))
                }
            } else {
                errors.append(CommitMessageError(
                    code: .invalidFormat,
                    message: "Unknown commit type '\(type)'. "
                        + "Valid types: \(CommitType.allCases.map { $0.rawValue }.joined(separator: ", "))",
                    range: typeRange
                ))
            }

            // Validate scope (if present)
            if typeMatch.numberOfRanges > 2 {
                let scopeRange = Range(typeMatch.range(at: 2), in: subject)
                if let scopeRange = scopeRange {
                    var scope = String(subject[scopeRange])
                    // Remove parentheses
                    scope = scope.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    if !scope.isEmpty {
                        // Scope length check
                        if let constraint = config.scopeConstraint, scope.count > constraint.maxLength {
                            errors.append(CommitMessageError(
                                code: .invalidFormat,
                                message: "Scope '\(scope)' exceeds maximum length of \(constraint.maxLength) characters.",
                                range: scopeRange
                            ))
                        }

                        // Allowed scopes check
                        if let constraint = config.scopeConstraint, let allowed = constraint.allowedScopes, !allowed.isEmpty {
                            if !allowed.contains(scope) {
                                errors.append(CommitMessageError(
                                    code: .invalidFormat,
                                    message: "Scope '\(scope)' is not in the allowed list: \(allowed.sorted().joined(separator: ", "))",
                                    range: scopeRange
                                ))
                            }
                        }
                    }
                }
            }

            // Breaking change indicator
            if typeMatch.numberOfRanges > 3 {
                let bangRange = Range(typeMatch.range(at: 3), in: subject)
                if let bangRange = bangRange {
                    let bang = String(subject[bangRange])
                    if bang == "!" {
                        // Breaking change — warn in body
                    }
                }
            }
        }

        // Description part (after ": ")
        let colonIndex = subject.firstIndex(of: ":")
        if let colon = colonIndex {
            let descStart = subject.index(after: colon)
            let description = String(subject[descStart...]).trimmingCharacters(in: .whitespaces)
            if description.isEmpty {
                errors.append(CommitMessageError(
                    code: .invalidFormat,
                    message: "Description after ': ' cannot be empty.",
                    range: nil
                ))
            }
        }

        return errors
    }

    // MARK: - Forbidden Patterns

    private func validateForbiddenPatterns(_ message: String) -> [CommitMessageError] {
        var errors: [CommitMessageError] = []

        for pattern in config.forbiddenPatterns {
            if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b", options: []) {
                let range = NSRange(message.startIndex..<message.endIndex, in: message)
                let matches = regex.matches(in: message, options: [], range: range)
                if !matches.isEmpty {
                    errors.append(CommitMessageError(
                        code: .containsForbiddenPatterns,
                        message: "Commit message contains forbidden pattern '\(pattern)'. "
                            + "These should be resolved before committing.",
                        range: nil
                    ))
                }
            }
        }

        return errors
    }

    // MARK: - Warnings

    private func generateWarnings(subjectLine: String, bodyLines: [String]) -> [CommitMessageWarning] {
        var warnings: [CommitMessageWarning] = []

        // Imperative mood check
        let lowercased = subjectLine.lowercased()

        // Check if subject starts with past tense
        let pastTenseWords = ["added", "updated", "fixed", "removed", "implemented", "refactored", "improved"]
        for word in pastTenseWords {
            if lowercased.contains(word) {
                warnings.append(CommitMessageWarning(
                    code: .imperativeMood,
                    message: "Subject appears to use past tense ('\(word)'). "
                        + "Use imperative mood instead (e.g., 'add' not 'added'). "
                        + "Think: 'This commit will add' → 'add'."
                ))
                break
            }
        }

        // Body ends without proper punctuation
        if let lastBodyLine = bodyLines.last?.trimmingCharacters(in: .whitespaces) {
            if !lastBodyLine.isEmpty && !lastBodyLine.hasSuffix(".") && !lastBodyLine.hasSuffix("!") && !lastBodyLine.hasSuffix("?") {
                warnings.append(CommitMessageWarning(
                    code: .bodyEndsPoorly,
                    message: "Body does not end with punctuation. Consider ending with a period."
                ))
            }
        }

        return warnings
    }

    // MARK: - Helpers

    private func deduplicateErrors(_ errors: [CommitMessageError]) -> [CommitMessageError] {
        var seen: [CommitMessageError.ErrorCode: Int] = [:]
        return errors.enumerated().compactMap { index, error in
            if let firstIndex = seen[error.code], firstIndex < index {
                return nil
            }
            seen[error.code] = index
            return error
        }
    }
}
