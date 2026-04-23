import Foundation

/// Represents information about a file found during search
public struct FileInfo: Sendable, Equatable, Codable {
    /// Path to the file
    public let path: String

    /// File name (last path component)
    public let name: String

    /// File extension (without the leading dot)
    public let extension_: String?

    /// File size in bytes
    public let size: Int64

    /// Last modification date
    public let modifiedAt: Date

    /// Whether the file is a directory
    public let isDirectory: Bool

    /// Whether the file is a symbolic link
    public let isSymbolicLink: Bool

    /// Permissions string (e.g., "rw-r--r--")
    public let permissions: String

    /// Line count (only for regular text files, nil for binary/directories)
    public let lineCount: Int?

    /// Encoding of the file (nil for binary files)
    public let encoding: String?

    enum CodingKeys: String, CodingKey {
        case path, name, extension_ = "extension", size, modifiedAt, isDirectory, isSymbolicLink, permissions, lineCount, encoding
    }

    public init(
        path: String,
        name: String,
        extension_: String?,
        size: Int64,
        modifiedAt: Date,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        permissions: String,
        lineCount: Int?,
        encoding: String?
    ) {
        self.path = path
        self.name = name
        self.extension_ = extension_
        self.size = size
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.permissions = permissions
        self.lineCount = lineCount
        self.encoding = encoding
    }
}

/// Options for search_files operations
public struct SearchFilesOptions: Sendable {
    /// Pattern type (glob, regex, or literal)
    public enum PatternType: Sendable {
        case glob       // Default, shell-style wildcards
        case regex      // Regular expression
        case literal    // Literal string match
    }

    /// Whether to search recursively (default: true)
    public let recursive: Bool

    /// Maximum depth for recursive search (0 = unlimited)
    public let maxDepth: Int

    /// File extensions to include (e.g., [".swift", ".m"])
    public let extensions: [String]?

    /// Pattern type for matching
    public let patternType: PatternType

    /// Include hidden files (files starting with .)
    public let includeHidden: Bool

    /// Directories to exclude from search
    public let excludeDirs: [String]

    /// Files to exclude from search (patterns)
    public let excludeFiles: [String]

    /// Maximum number of results to return (0 = unlimited)
    public let maxResults: Int

    /// Include file statistics (size, dates, permissions)
    public let includeStats: Bool

    /// Include line counts for text files
    public let includeLineCount: Bool

    public init(
        recursive: Bool = true,
        maxDepth: Int = 0,
        extensions: [String]? = nil,
        patternType: PatternType = .glob,
        includeHidden: Bool = false,
        excludeDirs: [String] = [],
        excludeFiles: [String] = [],
        maxResults: Int = 0,
        includeStats: Bool = true,
        includeLineCount: Bool = true
    ) {
        self.recursive = recursive
        self.maxDepth = maxDepth
        self.extensions = extensions
        self.patternType = patternType
        self.includeHidden = includeHidden
        self.excludeDirs = excludeDirs
        self.excludeFiles = excludeFiles
        self.maxResults = maxResults
        self.includeStats = includeStats
        self.includeLineCount = includeLineCount
    }

    /// Default options
    public static let `default` = SearchFilesOptions()
}

/// Search files tool for finding files by name pattern
///
/// Searches for files matching a pattern at a given path, supporting glob,
/// regex, and literal pattern matching with various filtering options.
///
/// Phase 4: Agentic Coding Engine — Tool definitions, sandbox, task state machine
/// Task: search_files(pattern: String, path: String) -> [FileInfo]
///
/// Usage:
///   let tool = SearchFilesTool()
///   let results = tool.searchFiles(pattern: "*.swift", path: "/path/to/project")
///   for result in results {
///       print("\(result.path) (\(result.size) bytes)")
///   }
public struct SearchFilesTool: Sendable {

    public let options: SearchFilesOptions

    /// Default excluded directories
    public static let defaultExcludeDirs = [
        ".git",
        ".svn",
        "node_modules",
        ".build",
        "DerivedData",
        "Pods",
        "Carthage",
        ".cache",
        ".idea",
        ".vscode"
    ]

    public init(options: SearchFilesOptions = .default) {
        self.options = options
    }

    // MARK: - Public API

    /// Search for files matching a pattern
    /// - Parameters:
    ///   - pattern: The search pattern (glob, regex, or literal depending on options)
    ///   - path: Root path to search in
    /// - Returns: Array of FileInfo for each matching file
    public func searchFiles(pattern: String, path: String) -> [FileInfo] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: path) else {
            return []
        }

        var results: [FileInfo] = []
        let allFiles = collectFiles(at: rootURL, fileManager: fileManager, currentDepth: 0)

        for fileURL in allFiles {
            if matchesPattern(fileURL: fileURL, pattern: pattern) {
                let fileInfo = buildFileInfo(from: fileURL)
                results.append(fileInfo)

                if options.maxResults > 0 && results.count >= options.maxResults {
                    return Array(results.prefix(options.maxResults))
                }
            }
        }

        return results
    }

    /// Quick search with just pattern and path (uses default options)
    public static func searchFiles(pattern: String, path: String) -> [FileInfo] {
        SearchFilesTool().searchFiles(pattern: pattern, path: path)
    }

    // MARK: - Private Methods

    private func collectFiles(at url: URL, fileManager: FileManager, currentDepth: Int) -> [URL] {
        var files: [URL] = []

        if !options.recursive && currentDepth > 0 {
            return files
        }

        if options.maxDepth > 0 && currentDepth > options.maxDepth {
            return files
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: options.includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return files
        }

        let excludeDirSet = Set((options.excludeDirs.isEmpty ? Self.defaultExcludeDirs : options.excludeDirs))
        let excludeFilePatterns: [String] = options.excludeFiles.flatMap { compilePattern($0) }

        for case let fileURL as URL in enumerator {
            // Check depth limit
            if currentDepth >= options.maxDepth && options.maxDepth > 0 {
                enumerator.skipDescendants()
                continue
            }

            guard let fileResourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
                continue
            }

            if fileResourceValues.isDirectory == true {
                let lastPathComponent = fileURL.lastPathComponent
                if excludeDirSet.contains(lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if fileResourceValues.isRegularFile == true || fileResourceValues.isSymbolicLink == true {
                // Check extension filter
                if let extensions = options.extensions {
                    let ext = fileURL.pathExtension
                    let extWithDot = ext.isEmpty ? "" : ".\(ext)"
                    if !ext.isEmpty && !extensions.contains(extWithDot) && !extensions.contains(ext) && !extensions.contains(".\(ext)") {
                        continue
                    }
                }

                // Check exclude files patterns - skip if any pattern matches
                if !excludeFilePatterns.isEmpty {
                    let fileName = fileURL.lastPathComponent
                    var shouldExclude = false
                    for pattern in excludeFilePatterns {
                        if matchesSinglePattern(fileName, pattern: pattern) {
                            shouldExclude = true
                            break
                        }
                    }
                    if shouldExclude {
                        continue
                    }
                }

                files.append(fileURL)
            }
        }

        return files
    }

    private func matchesPattern(fileURL: URL, pattern: String) -> Bool {
        let fileName = fileURL.lastPathComponent

        switch options.patternType {
        case .glob:
            return matchesGlob(fileName: fileName, glob: pattern)
        case .regex:
            return matchesRegex(fileName: fileName, regex: pattern)
        case .literal:
            return fileName.localizedCaseInsensitiveContains(pattern)
        }
    }

    private func matchesGlob(fileName: String, glob: String) -> Bool {
        // Convert glob pattern to regex
        // Supported: **, *, ?, [abc], [!abc]
        var regexPattern = ""
        var i = glob.startIndex
        var inCharacterClass = false

        while i < glob.endIndex {
            let char = glob[i]

            if inCharacterClass {
                if char == "]" {
                    inCharacterClass = false
                    regexPattern += "]"
                } else if char == "-" && i > glob.startIndex && glob[glob.index(before: i)] != "[" {
                    regexPattern += "-"
                } else {
                    regexPattern += NSRegularExpression.escapedPattern(for: String(char))
                }
                i = glob.index(after: i)
                continue
            }

            switch char {
            case "*":
                // Check for ** (match any path)
                if i < glob.index(before: glob.endIndex), glob[glob.index(after: i)] == "*" {
                    // ** matches any characters including path separators
                    regexPattern += ".*"
                    i = glob.index(after: i)
                    i = glob.index(after: i)
                    continue
                } else {
                    // * matches any characters except path separators
                    regexPattern += "[^/]*"
                }
            case "?":
                regexPattern += "[^/]"
            case "[":
                inCharacterClass = true
                regexPattern += "["
                if i < glob.index(before: glob.endIndex) && glob[glob.index(after: i)] == "!" {
                    regexPattern += "^"
                    i = glob.index(after: i)
                } else if i < glob.index(before: glob.endIndex) && glob[glob.index(after: i)] == "^" {
                    regexPattern += "^"
                    i = glob.index(after: i)
                }
            case ".":
                regexPattern += "\\."
            case "\\":
                regexPattern += "\\\\"
            default:
                regexPattern += NSRegularExpression.escapedPattern(for: String(char))
            }

            i = glob.index(after: i)
        }

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
            let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        } catch {
            // If regex fails, fall back to literal matching
            return fileName.localizedCaseInsensitiveContains(glob)
        }
    }

    private func matchesRegex(fileName: String, regex pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    private func compilePattern(_ pattern: String) -> [String] {
        // Split pattern by | and return individual patterns
        return pattern.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func matchesSinglePattern(_ string: String, pattern: String) -> Bool {
        switch options.patternType {
        case .glob:
            return matchesGlob(fileName: string, glob: pattern)
        case .regex:
            return matchesRegex(fileName: string, regex: pattern)
        case .literal:
            return string.localizedCaseInsensitiveContains(pattern)
        }
    }

    private func buildFileInfo(from url: URL) -> FileInfo {
        let fileManager = FileManager.default
        var name = url.lastPathComponent
        var extension_: String? = url.pathExtension.isEmpty ? nil : url.pathExtension
        var size: Int64 = 0
        var modifiedAt = Date()
        var isDirectory = false
        var isSymbolicLink = false
        var permissions = "---------"
        var lineCount: Int? = nil
        var encoding: String? = nil

        // Get file attributes
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path) {
            size = attrs[.size] as? Int64 ?? 0
            modifiedAt = attrs[.modificationDate] as? Date ?? Date()
            isDirectory = attrs[.type] as? FileAttributeType == .typeDirectory
            if let mode = attrs[.posixPermissions] as? UInt {
                permissions = formatPermissions(mode)
            }
        }

        // Check if symbolic link
        if let symAttrs = try? fileManager.attributesOfItem(atPath: url.path) {
            isSymbolicLink = symAttrs[.type] as? FileAttributeType == .typeSymbolicLink
        }

        if isSymbolicLink {
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
                name = "\(name) -> \(destination)"
            }
        }

        // Calculate line count for text files
        if options.includeLineCount && !isDirectory && !isSymbolicLink && !isBinaryFile(at: url) {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                lineCount = content.components(separatedBy: .newlines).count
                encoding = "utf-8"
            } else if let content = try? String(contentsOf: url, encoding: .ascii) {
                lineCount = content.components(separatedBy: .newlines).count
                encoding = "ascii"
            }
        }

        return FileInfo(
            path: url.path,
            name: name,
            extension_: extension_,
            size: size,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            permissions: permissions,
            lineCount: options.includeLineCount ? lineCount : nil,
            encoding: encoding
        )
    }

    private func formatPermissions(_ mode: UInt) -> String {
        let types = ["---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"]
        var result = ""

        let owner = (mode & 0o700) >> 6
        let group = (mode & 0o070) >> 3
        let other = mode & 0o007

        result += types[Int(owner)]
        result += types[Int(group)]
        result += types[Int(other)]

        return result
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

        return data.withUnsafeBytes { buffer in
            buffer.contains(where: { $0 == 0 })
        }
    }
}

// MARK: - Convenience Extensions

extension SearchFilesTool {

    /// Search for files by extension
    public func searchByExtension(_ extensions: [String], path: String) -> [FileInfo] {
        let newOpts = SearchFilesOptions(
            recursive: options.recursive,
            maxDepth: options.maxDepth,
            extensions: extensions,
            patternType: options.patternType,
            includeHidden: options.includeHidden,
            excludeDirs: options.excludeDirs,
            excludeFiles: options.excludeFiles,
            maxResults: options.maxResults,
            includeStats: options.includeStats,
            includeLineCount: options.includeLineCount
        )
        return SearchFilesTool(options: newOpts).searchFiles(pattern: "*", path: path)
    }

    /// Search recursively with depth limit
    public func searchWithDepth(_ maxDepth: Int, pattern: String, path: String) -> [FileInfo] {
        let newOpts = SearchFilesOptions(
            recursive: true,
            maxDepth: maxDepth,
            extensions: options.extensions,
            patternType: options.patternType,
            includeHidden: options.includeHidden,
            excludeDirs: options.excludeDirs,
            excludeFiles: options.excludeFiles,
            maxResults: options.maxResults,
            includeStats: options.includeStats,
            includeLineCount: options.includeLineCount
        )
        return SearchFilesTool(options: newOpts).searchFiles(pattern: pattern, path: path)
    }

    /// Search using regex pattern
    public func searchRegex(_ regex: String, path: String) -> [FileInfo] {
        let newOpts = SearchFilesOptions(
            recursive: options.recursive,
            maxDepth: options.maxDepth,
            extensions: options.extensions,
            patternType: .regex,
            includeHidden: options.includeHidden,
            excludeDirs: options.excludeDirs,
            excludeFiles: options.excludeFiles,
            maxResults: options.maxResults,
            includeStats: options.includeStats,
            includeLineCount: options.includeLineCount
        )
        return SearchFilesTool(options: newOpts).searchFiles(pattern: regex, path: path)
    }
}
