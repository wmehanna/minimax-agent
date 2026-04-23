import Foundation

/// Represents a single grep match result
public struct MatchResult: Sendable, Equatable {
    /// Path to the file containing the match
    public let filePath: String

    /// Line number (1-indexed) where the match was found
    public let lineNumber: Int

    /// The full line content
    public let lineContent: String

    /// The matched text within the line
    public let matchedText: String

    /// Column range of the match within the line (0-indexed)
    public let range: Range<Int>

    /// Context around the match (before and after lines)
    public let contextBefore: [String]
    public let contextAfter: [String]

    public init(
        filePath: String,
        lineNumber: Int,
        lineContent: String,
        matchedText: String,
        range: Range<Int>,
        contextBefore: [String] = [],
        contextAfter: [String] = []
    ) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.matchedText = matchedText
        self.range = range
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

/// Options for grep operations
public struct GrepOptions: Sendable {
    /// Whether the search is case-sensitive (default: true)
    public let caseSensitive: Bool

    /// Treat pattern as a regular expression (default: true)
    public let isRegex: Bool

    /// Include binary files in search (default: false)
    public let includeBinary: Bool

    /// File extensions to filter (e.g., [".swift", ".m"])
    public let extensions: [String]?

    /// Directories to exclude from search
    public let excludeDirs: [String]

    /// Maximum number of results to return (0 = unlimited)
    public let maxResults: Int

    /// Number of context lines before/after match
    public let contextLines: Int

    /// Invert match (find non-matching lines)
    public let invertMatch: Bool

    public init(
        caseSensitive: Bool = true,
        isRegex: Bool = true,
        includeBinary: Bool = false,
        extensions: [String]? = nil,
        excludeDirs: [String] = [],
        maxResults: Int = 0,
        contextLines: Int = 0,
        invertMatch: Bool = false
    ) {
        self.caseSensitive = caseSensitive
        self.isRegex = isRegex
        self.includeBinary = includeBinary
        self.extensions = extensions
        self.excludeDirs = excludeDirs
        self.maxResults = maxResults
        self.contextLines = contextLines
        self.invertMatch = invertMatch
    }

    /// Default options
    public static let `default` = GrepOptions()
}

/// Grep tool for searching file contents
///
/// Searches for a pattern within files at a given path, supporting both
/// literal string and regex matching with various filtering options.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: grep(pattern: String, path: String) -> [MatchResult]
///
/// Usage:
///   let tool = GrepTool()
///   let results = tool.grep(pattern: "func ", path: "/path/to/project")
///   for result in results {
///       print("\(result.filePath):\(result.lineNumber): \(result.lineContent)")
///   }
public struct GrepTool: Sendable {

    public let options: GrepOptions

    /// Default excluded directories
    public static let defaultExcludeDirs = [
        ".git",
        ".svn",
        "node_modules",
        ".build",
        "DerivedData",
        "Pods",
        "Carthage",
        ".cache"
    ]

    public init(options: GrepOptions = .default) {
        self.options = options
    }

    // MARK: - Public API

    /// Search for a pattern in files at the given path
    /// - Parameters:
    ///   - pattern: The search pattern (literal or regex depending on options)
    ///   - path: Root path to search in
    /// - Returns: Array of MatchResult for each match found
    public func grep(pattern: String, path: String) -> [MatchResult] {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: path) else {
            return []
        }

        var results: [MatchResult] = []
        let allFiles = collectFiles(at: url, fileManager: fileManager)

        for fileURL in allFiles {
            let fileResults = searchFile(fileURL: fileURL, pattern: pattern)
            results.append(contentsOf: fileResults)

            if options.maxResults > 0 && results.count >= options.maxResults {
                return Array(results.prefix(options.maxResults))
            }
        }

        return results
    }

    /// Quick grep with just pattern and path (uses default options)
    public static func grep(pattern: String, path: String) -> [MatchResult] {
        GrepTool().grep(pattern: pattern, path: path)
    }

    /// Search using system grep command (faster for large codebases)
    public func grepWithSystem(pattern: String, path: String) -> [MatchResult] {
        var arguments = ["--line-number"]

        if !options.caseSensitive {
            arguments.append("--ignore-case")
        }

        if options.isRegex {
            arguments.append("--extended-regexp")
        } else {
            arguments.append("--fixed-strings")
        }

        if options.invertMatch {
            arguments.append("--invert-match")
        }

        // Add exclude patterns
        for excludeDir in options.excludeDirs.isEmpty ? Self.defaultExcludeDirs : options.excludeDirs {
            arguments.append("--exclude-dir=\(excludeDir)")
        }

        if let extensions = options.extensions {
            for ext in extensions {
                arguments.append("--include=\(ext)")
            }
        }

        arguments.append(pattern)
        arguments.append(path)

        let result = runCommand("/usr/bin/grep", arguments: arguments)

        guard result.exitCode == 0 || result.exitCode == 1 else {
            // 1 means no matches, which is fine
            return []
        }

        return parseGrepOutput(result.stdout, basePath: path)
    }

    // MARK: - Private Methods

    private func collectFiles(at url: URL, fileManager: FileManager) -> [URL] {
        var files: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        let excludeSet = Set(options.excludeDirs.isEmpty ? Self.defaultExcludeDirs : options.excludeDirs)

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

                if resourceValues.isDirectory == true {
                    let lastPathComponent = fileURL.lastPathComponent
                    if excludeSet.contains(lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if resourceValues.isRegularFile == true {
                    // Check extension filter
                    if let extensions = options.extensions {
                        let ext = fileURL.pathExtension
                        if !ext.isEmpty && !extensions.contains(".\(ext)") && !extensions.contains(ext) {
                            continue
                        }
                    }

                    // Skip binary files unless explicitly included
                    if !options.includeBinary && isBinaryFile(at: fileURL) {
                        continue
                    }

                    files.append(fileURL)
                }
            } catch {
                continue
            }
        }

        return files
    }

    private func searchFile(fileURL: URL, pattern: String) -> [MatchResult] {
        var results: [MatchResult] = []

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return results
        }

        let regex: NSRegularExpression?
        if options.isRegex {
            let flags: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
            regex = try? NSRegularExpression(pattern: pattern, options: flags)
        } else {
            // Escape literal string for regex
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let flags: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
            regex = try? NSRegularExpression(pattern: escaped, options: flags)
        }

        guard let regex = regex else {
            return results
        }

        let lines = content.components(separatedBy: .newlines)
        let filePath = fileURL.path

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: range)

            let hasMatches = !matches.isEmpty
            let shouldInclude = options.invertMatch ? !hasMatches : hasMatches

            if shouldInclude {
                for match in matches {
                    if let swiftRange = Range(match.range, in: line) {
                        let contextBefore = getContextLines(lines: lines, currentIndex: index, count: options.contextLines, direction: .before)
                        let contextAfter = getContextLines(lines: lines, currentIndex: index, count: options.contextLines, direction: .after)

                        let result = MatchResult(
                            filePath: filePath,
                            lineNumber: lineNumber,
                            lineContent: line,
                            matchedText: String(line[swiftRange]),
                            range: swiftRange.lowerBound.utf16Offset(in: line)..<swiftRange.upperBound.utf16Offset(in: line),
                            contextBefore: contextBefore,
                            contextAfter: contextAfter
                        )
                        results.append(result)
                    }
                }

                if options.invertMatch && matches.isEmpty {
                    // For inverted match, we report the whole line
                    let contextBefore = getContextLines(lines: lines, currentIndex: index, count: options.contextLines, direction: .before)
                    let contextAfter = getContextLines(lines: lines, currentIndex: index, count: options.contextLines, direction: .after)

                    let result = MatchResult(
                        filePath: filePath,
                        lineNumber: lineNumber,
                        lineContent: line,
                        matchedText: "",
                        range: 0..<0,
                        contextBefore: contextBefore,
                        contextAfter: contextAfter
                    )
                    results.append(result)
                }
            }

            if options.maxResults > 0 && results.count >= options.maxResults {
                break
            }
        }

        return results
    }

    private enum ContextDirection {
        case before
        case after
    }

    private func getContextLines(lines: [String], currentIndex: Int, count: Int, direction: ContextDirection) -> [String] {
        guard count > 0 else { return [] }

        var context: [String] = []

        switch direction {
        case .before:
            let start = max(0, currentIndex - count)
            for i in start..<currentIndex {
                context.append(lines[i])
            }
        case .after:
            let end = min(lines.count, currentIndex + count + 1)
            for i in (currentIndex + 1)..<end {
                context.append(lines[i])
            }
        }

        return context
    }

    private func isBinaryFile(at url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return true
        }
        defer { try? fileHandle.close() }

        let chunkSize = 8192
        guard let data = try? fileHandle.read(upToCount: chunkSize) else {
            return true
        }

        // Check for null bytes which indicate binary content
        return data.withUnsafeBytes { buffer in
            buffer.contains(where: { $0 == 0 })
        }
    }

    private func runCommand(_ path: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let task = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("", "Failed to execute: \(error)", -1)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout, stderr, task.terminationStatus)
    }

    private func parseGrepOutput(_ output: String, basePath: String) -> [MatchResult] {
        var results: [MatchResult] = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            guard !line.isEmpty else { continue }

            // grep output format: filePath:lineNumber:content
            let colonIndex = line.firstIndex(of: ":")
            guard let firstColon = colonIndex else { continue }

            let filePath = String(line[..<firstColon])
            let remainder = String(line[line.index(after: firstColon)...])

            // Find the line number (digits at start of remainder)
            let digits = remainder.prefix(while: { $0.isNumber })
            guard !digits.isEmpty else { continue }

            let lineNumber = Int(digits) ?? 0
            let contentStartIndex = remainder.index(remainder.startIndex, offsetBy: digits.count)

            // Skip the second colon
            let content: String
            if remainder.count > digits.count && remainder[contentStartIndex] == ":" {
                content = String(remainder[remainder.index(after: contentStartIndex)...]).trimmingCharacters(in: .whitespaces)
            } else {
                content = String(remainder[contentStartIndex...]).trimmingCharacters(in: .whitespaces)
            }

            let result = MatchResult(
                filePath: filePath,
                lineNumber: lineNumber,
                lineContent: content,
                matchedText: "",
                range: 0..<0,
                contextBefore: [],
                contextAfter: []
            )
            results.append(result)
        }

        return results
    }
}

// MARK: - Convenience Extensions

extension GrepTool {

    /// Case-insensitive grep
    public func grepCaseInsensitive(pattern: String, path: String) -> [MatchResult] {
        var opts = options
        let newOpts = GrepOptions(
            caseSensitive: false,
            isRegex: opts.isRegex,
            includeBinary: opts.includeBinary,
            extensions: opts.extensions,
            excludeDirs: opts.excludeDirs,
            maxResults: opts.maxResults,
            contextLines: opts.contextLines,
            invertMatch: opts.invertMatch
        )
        return GrepTool(options: newOpts).grep(pattern: pattern, path: path)
    }

    /// Grep with file extension filter
    public func grepExtensions(_ extensions: [String], pattern: String, path: String) -> [MatchResult] {
        let newOpts = GrepOptions(
            caseSensitive: options.caseSensitive,
            isRegex: options.isRegex,
            includeBinary: options.includeBinary,
            extensions: extensions,
            excludeDirs: options.excludeDirs,
            maxResults: options.maxResults,
            contextLines: options.contextLines,
            invertMatch: options.invertMatch
        )
        return GrepTool(options: newOpts).grep(pattern: pattern, path: path)
    }
}
