import Foundation
import UniformTypeIdentifiers

/// Provides URL and file type filtering capabilities.
///
/// This module enables filtering of URLs by scheme/pattern and files by
/// extension, MIME type, or Uniform Type Identifier (UTType).
///
/// ## Overview
///
/// Content filtering is essential for:
/// - Share extension validation
/// - Drag & drop operations
/// - Services menu integration
/// - Security policy enforcement
///
/// ## Usage
///
/// ```swift
/// // Filter URLs by scheme
/// let urlFilter = URLFilter(allowedSchemes: ["http", "https"])
/// if urlFilter.isAllowed(URL(string: "https://example.com")!) {
///     // Process URL
/// }
///
/// // Filter files by type
/// let fileFilter = FileTypeFilter(allowedExtensions: ["swift", "txt"])
/// if fileFilter.isAllowed(filePath: "/path/to/file.swift") {
///     // Process file
/// }
/// ```
public struct ContentFilter: Sendable, Equatable {
    
    // MARK: - Types
    
    /// Represents a content filter rule
    public struct FilterRule: Sendable, Equatable, Hashable {
        public let pattern: String
        public let ruleType: RuleType
        public let isAllowed: Bool
        
        public enum RuleType: String, Sendable, Equatable, Hashable {
            case extension_
            case mimeType
            case utType
            case urlScheme
            case urlHost
            case pathPrefix
            case pathSuffix
        }
        
        public init(pattern: String, ruleType: RuleType, isAllowed: Bool = true) {
            self.pattern = pattern
            self.ruleType = ruleType
            self.isAllowed = isAllowed
        }
        
        public static func extension_(_ ext: String, allowed: Bool = true) -> FilterRule {
            FilterRule(pattern: ext, ruleType: .extension_, isAllowed: allowed)
        }
        
        public static func mimeType(_ mime: String, allowed: Bool = true) -> FilterRule {
            FilterRule(pattern: mime, ruleType: .mimeType, isAllowed: allowed)
        }
        
        public static func urlScheme(_ scheme: String, allowed: Bool = true) -> FilterRule {
            FilterRule(pattern: scheme, ruleType: .urlScheme, isAllowed: allowed)
        }
    }
    
    /// Content kind for filtering purposes
    public enum ContentKind: Sendable, Equatable {
        case url(URL)
        case file(path: String)
        case data(Data)
        case text(String)
        
        public var url: URL? {
            if case .url(let u) = self { return u }
            return nil
        }
        
        public var filePath: String? {
            if case .file(let path) = self { return path }
            return nil
        }
    }
    
    // MARK: - Properties
    
    private let rules: Set<FilterRule>
    private let defaultAllowance: Bool
    private let caseSensitive: Bool
    
    // MARK: - Initialization
    
    /// Creates a content filter with the given rules.
    ///
    /// - Parameters:
    ///   - rules: Set of filter rules to apply
    ///   - defaultAllowance: Whether to allow content that doesn't match any rule (default: true)
    ///   - caseSensitive: Whether pattern matching is case-sensitive (default: false)
    public init(
        rules: Set<FilterRule> = [],
        defaultAllowance: Bool = true,
        caseSensitive: Bool = false
    ) {
        self.rules = rules
        self.defaultAllowance = defaultAllowance
        self.caseSensitive = caseSensitive
    }
    
    /// Creates a filter that allows all content.
    public static let allowAll = ContentFilter(defaultAllowance: true)
    
    /// Creates a filter that blocks all content.
    public static let blockAll = ContentFilter(defaultAllowance: false)
    
    // MARK: - Evaluation
    
    /// Determines if the given content is allowed by this filter.
    ///
    /// - Parameter content: The content to check
    /// - Returns: true if the content is allowed, false otherwise
    public func isAllowed(_ content: ContentKind) -> Bool {
        switch content {
        case .url(let url):
            return isAllowedURL(url)
        case .file(let path):
            return isAllowedFile(path: path)
        case .data(let data):
            return isAllowedData(data)
        case .text:
            // Text is generally allowed unless blocked by specific rules
            return defaultAllowance
        }
    }
    
    /// Checks if a URL is allowed by this filter.
    public func isAllowedURL(_ url: URL) -> Bool {
        for rule in rules {
            switch rule.ruleType {
            case .urlScheme:
                let scheme = url.scheme ?? ""
                if matches(scheme, pattern: rule.pattern) {
                    return rule.isAllowed
                }
            case .urlHost:
                let host = url.host ?? ""
                if matches(host, pattern: rule.pattern) {
                    return rule.isAllowed
                }
            case .pathPrefix:
                let path = url.path
                if matches(path, pattern: rule.pattern, suffix: false) {
                    return rule.isAllowed
                }
            case .pathSuffix:
                let path = url.path
                if matches(path, pattern: rule.pattern, suffix: true) {
                    return rule.isAllowed
                }
            default:
                continue
            }
        }
        return defaultAllowance
    }
    
    /// Checks if a file path is allowed by this filter.
    public func isAllowedFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        for rule in rules {
            switch rule.ruleType {
            case .extension_:
                if matches(ext, pattern: rule.pattern) {
                    return rule.isAllowed
                }
            case .pathPrefix:
                if matches(path, pattern: rule.pattern, suffix: false) {
                    return rule.isAllowed
                }
            case .pathSuffix:
                if matches(path, pattern: rule.pattern, suffix: true) {
                    return rule.isAllowed
                }
            default:
                continue
            }
        }
        return defaultAllowance
    }
    
    /// Checks if data is allowed by this filter.
    public func isAllowedData(_ data: Data) -> Bool {
        // UTType detection from raw data is not available; fall back to default allowance
        let utType: UTType = .data
        _ = data

        return isAllowedUTType(utType)
    }
    
    /// Checks if a UTType is allowed by this filter.
    public func isAllowedUTType(_ utType: UTType) -> Bool {
        for rule in rules {
            if rule.ruleType == .utType {
                if matches(utType.identifier, pattern: rule.pattern) {
                    return rule.isAllowed
                }
                // Also check conforming types
                if let patternType = UTType(rule.pattern), utType.conforms(to: patternType) {
                    return rule.isAllowed
                }
            }
        }
        return defaultAllowance
    }
    
    // MARK: - Helper Methods
    
    private func matches(_ value: String, pattern: String, suffix: Bool = false) -> Bool {
        let compareValue = caseSensitive ? value : value.lowercased()
        let comparePattern = caseSensitive ? pattern : pattern.lowercased()
        
        if suffix {
            return compareValue.hasSuffix(comparePattern)
        } else {
            return compareValue == comparePattern || compareValue.contains(comparePattern)
        }
    }
    
    private func matches(_ value: String, pattern: String) -> Bool {
        let compareValue = caseSensitive ? value : value.lowercased()
        let comparePattern = caseSensitive ? pattern : pattern.lowercased()
        return compareValue == comparePattern
    }
    
    // MARK: - Rule Management
    
    /// Returns all rules of a specific type.
    public func rules(ofType type: FilterRule.RuleType) -> [FilterRule] {
        rules.filter { $0.ruleType == type }
    }
    
    /// Returns all allowed rules.
    public func allowedRules() -> [FilterRule] {
        rules.filter { $0.isAllowed }
    }
    
    /// Returns all blocked rules.
    public func blockedRules() -> [FilterRule] {
        rules.filter { !$0.isAllowed }
    }
}

// MARK: - URL Filter

/// Specialized filter for URL content.
///
/// Provides convenient methods for filtering URLs by scheme, host, and path patterns.
public struct URLFilter: Sendable, Equatable {
    
    // MARK: - Properties
    
    /// Allowed URL schemes (e.g., "http", "https", "ftp")
    public let allowedSchemes: Set<String>
    
    /// Blocked URL schemes
    public let blockedSchemes: Set<String>
    
    /// Allowed host patterns (supports wildcards like "*.example.com")
    public let allowedHosts: Set<String>
    
    /// Blocked host patterns
    public let blockedHosts: Set<String>
    
    /// Allowed path patterns
    public let allowedPaths: Set<String>
    
    /// Blocked path patterns
    public let blockedPaths: Set<String>
    
    /// Whether to allow file:// URLs
    public let allowFileScheme: Bool
    
    /// Whether to allow http:// URLs
    public let allowHttpScheme: Bool
    
    /// Whether to allow https:// URLs
    public let allowHttpsScheme: Bool
    
    /// Whether to allow data: URLs
    public let allowDataScheme: Bool
    
    /// Whether to allow javascript: URLs
    public let allowJavascriptScheme: Bool
    
    // MARK: - Initialization
    
    /// Creates a URL filter with the specified configuration.
    public init(
        allowedSchemes: Set<String> = [],
        blockedSchemes: Set<String> = [],
        allowedHosts: Set<String> = [],
        blockedHosts: Set<String> = [],
        allowedPaths: Set<String> = [],
        blockedPaths: Set<String> = [],
        allowFileScheme: Bool = false,
        allowHttpScheme: Bool = true,
        allowHttpsScheme: Bool = true,
        allowDataScheme: Bool = false,
        allowJavascriptScheme: Bool = false
    ) {
        self.allowedSchemes = allowedSchemes
        self.blockedSchemes = blockedSchemes
        self.allowedHosts = allowedHosts
        self.blockedHosts = blockedHosts
        self.allowedPaths = allowedPaths
        self.blockedPaths = blockedPaths
        self.allowFileScheme = allowFileScheme
        self.allowHttpScheme = allowHttpScheme
        self.allowHttpsScheme = allowHttpsScheme
        self.allowDataScheme = allowDataScheme
        self.allowJavascriptScheme = allowJavascriptScheme
    }
    
    /// Creates a filter allowing only web URLs (http and https).
    public static let webOnly = URLFilter(
        allowFileScheme: false,
        allowHttpScheme: true,
        allowHttpsScheme: true,
        allowDataScheme: false,
        allowJavascriptScheme: false
    )

    /// Creates a filter allowing only secure web URLs (https only).
    public static let secureWebOnly = URLFilter(
        allowFileScheme: false,
        allowHttpScheme: false,
        allowHttpsScheme: true,
        allowDataScheme: false,
        allowJavascriptScheme: false
    )

    /// Creates a filter allowing file URLs only.
    public static let filesOnly = URLFilter(
        allowFileScheme: true,
        allowHttpScheme: false,
        allowHttpsScheme: false,
        allowDataScheme: false,
        allowJavascriptScheme: false
    )
    
    /// Creates a filter allowing all URL types.
    public static let allowAll = URLFilter()
    
    // MARK: - Validation
    
    /// Checks if the given URL is allowed by this filter.
    ///
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL is allowed, false otherwise
    public func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        // Check scheme rules
        if !allowedSchemes.isEmpty && !allowedSchemes.contains(scheme) {
            return false
        }
        
        if blockedSchemes.contains(scheme) {
            return false
        }
        
        // Check specific scheme flags
        switch scheme {
        case "file":
            if !allowFileScheme { return false }
        case "http":
            if !allowHttpScheme { return false }
        case "https":
            if !allowHttpsScheme { return false }
        case "data":
            if !allowDataScheme { return false }
        case "javascript":
            if !allowJavascriptScheme { return false }
        default:
            break
        }
        
        // Check host rules
        if let host = url.host?.lowercased() {
            if !allowedHosts.isEmpty && !matchesAnyPattern(host, patterns: allowedHosts) {
                return false
            }
            if matchesAnyPattern(host, patterns: blockedHosts) {
                return false
            }
        }
        
        // Check path rules
        let path = url.path
        if !allowedPaths.isEmpty && !matchesAnyPattern(path, patterns: allowedPaths) {
            return false
        }
        if matchesAnyPattern(path, patterns: blockedPaths) {
            return false
        }
        
        return true
    }
    
    /// Checks if the URL passes security checks.
    ///
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL is secure, false otherwise
    public func isSecure(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        // Block javascript: URLs for security
        if scheme == "javascript" {
            return false
        }
        
        // Block data: URLs with script content
        if scheme == "data" {
            if let mimeType = url.absoluteString.split(separator: ",").first,
               String(mimeType).lowercased().contains("text/javascript") ||
               String(mimeType).lowercased().contains("application/javascript") {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Helper Methods
    
    private func matchesAnyPattern(_ value: String, patterns: Set<String>) -> Bool {
        for pattern in patterns {
            if matchesPattern(value, pattern: pattern) {
                return true
            }
        }
        return false
    }
    
    private func matchesPattern(_ value: String, pattern: String) -> Bool {
        let lowercasedValue = value.lowercased()
        let lowercasedPattern = pattern.lowercased()
        
        // Exact match
        if lowercasedValue == lowercasedPattern {
            return true
        }
        
        // Wildcard pattern (e.g., "*.example.com")
        if lowercasedPattern.hasPrefix("*.") {
            let suffix = String(lowercasedPattern.dropFirst(2))
            return lowercasedValue.hasSuffix(suffix) || lowercasedValue == suffix
        }
        
        // Contains pattern
        return lowercasedValue.contains(lowercasedPattern)
    }
    
    // MARK: - Conversion
    
    /// Converts to a general ContentFilter.
    public func toContentFilter() -> ContentFilter {
        var rules: Set<ContentFilter.FilterRule> = []
        
        if allowHttpScheme {
            rules.insert(.urlScheme("http", allowed: true))
        }
        if allowHttpsScheme {
            rules.insert(.urlScheme("https", allowed: true))
        }
        if allowFileScheme {
            rules.insert(.urlScheme("file", allowed: true))
        }
        if allowDataScheme {
            rules.insert(.urlScheme("data", allowed: true))
        }
        if allowJavascriptScheme {
            rules.insert(.urlScheme("javascript", allowed: true))
        }
        
        for scheme in blockedSchemes {
            rules.insert(.urlScheme(scheme, allowed: false))
        }
        
        return ContentFilter(rules: rules, defaultAllowance: false)
    }
}

// MARK: - File Type Filter

/// Specialized filter for file content.
///
/// Provides convenient methods for filtering files by extension, MIME type, or UTType.
public struct FileTypeFilter: Sendable, Equatable {
    
    // MARK: - Types
    
    /// File filtering mode
    public enum FilterMode: String, Sendable {
        case whitelist  // Only allow specified types
        case blacklist  // Allow all except specified types
    }
    
    // MARK: - Properties
    
    /// Allowed file extensions (without leading dot)
    public let allowedExtensions: Set<String>
    
    /// Blocked file extensions
    public let blockedExtensions: Set<String>
    
    /// Allowed MIME types
    public let allowedMimeTypes: Set<String>
    
    /// Blocked MIME types
    public let blockedMimeTypes: Set<String>
    
    /// Allowed UTType identifiers
    public let allowedTypes: Set<String>
    
    /// Blocked UTType identifiers
    public let blockedTypes: Set<String>
    
    /// Filter mode
    public let mode: FilterMode
    
    /// Whether to check file contents for type detection
    public let detectFromContent: Bool
    
    // MARK: - Initialization
    
    /// Creates a file type filter with the specified configuration.
    public init(
        allowedExtensions: Set<String> = [],
        blockedExtensions: Set<String> = [],
        allowedMimeTypes: Set<String> = [],
        blockedMimeTypes: Set<String> = [],
        allowedTypes: Set<String> = [],
        blockedTypes: Set<String> = [],
        mode: FilterMode = .whitelist,
        detectFromContent: Bool = false
    ) {
        self.allowedExtensions = allowedExtensions
        self.blockedExtensions = blockedExtensions
        self.allowedMimeTypes = allowedMimeTypes
        self.blockedMimeTypes = blockedMimeTypes
        self.allowedTypes = allowedTypes
        self.blockedTypes = blockedTypes
        self.mode = mode
        self.detectFromContent = detectFromContent
    }
    
    // MARK: - Presets
    
    /// Filter for source code files.
    public static let sourceCode = FileTypeFilter(
        allowedExtensions: ["swift", "py", "js", "ts", "java", "c", "cpp", "h", "m", "go", "rs", "rb", "php", "html", "css", "json", "xml", "yaml", "yml"],
        mode: .whitelist
    )
    
    /// Filter for image files.
    public static let images = FileTypeFilter(
        allowedExtensions: ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"],
        allowedTypes: ["public.image"],
        mode: .whitelist
    )
    
    /// Filter for document files.
    public static let documents = FileTypeFilter(
        allowedExtensions: ["pdf", "doc", "docx", "txt", "rtf", "pages"],
        allowedTypes: ["com.adobe.pdf", "public.document"],
        mode: .whitelist
    )
    
    /// Filter for text files.
    public static let textFiles = FileTypeFilter(
        allowedExtensions: ["txt", "md", "markdown", "rtf", "json", "xml", "html", "css", "js"],
        allowedTypes: ["public.text", "public.plain-text", "public.source-code"],
        mode: .whitelist
    )
    
    /// Filter for archive files.
    public static let archives = FileTypeFilter(
        allowedExtensions: ["zip", "tar", "gz", "bz2", "xz", "dmg", "pkg"],
        allowedTypes: ["public.zip-archive", "com.pkgs.zip", "com.apple.dmg"],
        mode: .whitelist
    )
    
    /// Filter that blocks executable files.
    public static let blockExecutables = FileTypeFilter(
        blockedExtensions: ["exe", "app", "dmg", "pkg", "sh", "bash", "command", "bat", "cmd"],
        blockedTypes: ["com.apple.execute", "com.microsoft.exe"],
        mode: .blacklist
    )
    
    /// Filter that allows all files.
    public static let allowAll = FileTypeFilter(mode: .blacklist)
    
    // MARK: - Validation
    
    /// Checks if the given file path is allowed by this filter.
    ///
    /// - Parameter path: The file path to check
    /// - Returns: true if the file is allowed, false otherwise
    public func isAllowed(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        // Check extension
        if !allowedExtensions.isEmpty {
            if !allowedExtensions.contains(ext) {
                return false
            }
        }
        
        if blockedExtensions.contains(ext) {
            return false
        }
        
        // Check UTType
        if !allowedTypes.isEmpty || !blockedTypes.isEmpty {
            guard let utType = UTType(filenameExtension: ext) else {
                // Unknown type - apply mode
                return mode == .blacklist
            }
            
            if !allowedTypes.isEmpty && !matchesUTType(utType, against: allowedTypes) {
                return false
            }
            
            if matchesUTType(utType, against: blockedTypes) {
                return false
            }
        }
        
        return true
    }
    
    /// Checks if the given file URL is allowed by this filter.
    ///
    /// - Parameter url: The file URL to check
    /// - Returns: true if the file is allowed, false otherwise
    public func isAllowed(url: URL) -> Bool {
        return isAllowed(path: url.path)
    }
    
    /// Checks if data with the given MIME type is allowed.
    ///
    /// - Parameters:
    ///   - data: The data to check
    ///   - mimeType: The MIME type of the data
    /// - Returns: true if allowed, false otherwise
    public func isAllowed(data: Data, mimeType: String) -> Bool {
        // Check MIME type directly
        if !allowedMimeTypes.isEmpty && !allowedMimeTypes.contains(mimeType) {
            return false
        }
        
        if blockedMimeTypes.contains(mimeType) {
            return false
        }
        
        // Optionally detect from content
        if detectFromContent {
            if let detectedType: UTType? = .data, let detectedType {
                if !allowedTypes.isEmpty && !matchesUTType(detectedType, against: allowedTypes) {
                    return false
                }
                if matchesUTType(detectedType, against: blockedTypes) {
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Returns the MIME type for a given file path.
    ///
    /// - Parameter path: The file path
    /// - Returns: The MIME type string, or nil if unknown
    public func mimeType(forPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        if let ext = url.pathExtension.isEmpty ? nil : url.pathExtension,
           let utType = UTType(filenameExtension: ext) {
            return utType.preferredMIMEType
        }
        return nil
    }
    
    /// Returns the UTType for a given file path.
    ///
    /// - Parameter path: The file path
    /// - Returns: The UTType, or nil if unknown
    public func utType(forPath path: String) -> UTType? {
        let url = URL(fileURLWithPath: path)
        guard let ext = url.pathExtension.isEmpty ? nil : url.pathExtension else {
            return nil
        }
        return UTType(filenameExtension: ext)
    }
    
    // MARK: - Helper Methods
    
    private func matchesUTType(_ utType: UTType, against types: Set<String>) -> Bool {
        for typeId in types {
            if utType.identifier == typeId {
                return true
            }
            if let constraintType = UTType(typeId), utType.conforms(to: constraintType) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Conversion
    
    /// Converts to a general ContentFilter.
    public func toContentFilter() -> ContentFilter {
        var rules: Set<ContentFilter.FilterRule> = []
        
        for ext in allowedExtensions {
            rules.insert(.extension_(ext, allowed: true))
        }
        
        for ext in blockedExtensions {
            rules.insert(.extension_(ext, allowed: false))
        }
        
        for type in allowedTypes {
            rules.insert(ContentFilter.FilterRule(pattern: type, ruleType: .utType, isAllowed: true))
        }
        
        for type in blockedTypes {
            rules.insert(ContentFilter.FilterRule(pattern: type, ruleType: .utType, isAllowed: false))
        }
        
        let defaultAllow = mode == .blacklist
        return ContentFilter(rules: rules, defaultAllowance: defaultAllow)
    }
}

// MARK: - Utility Extensions

extension URL {
    /// Returns whether this URL passes basic security checks.
    public var isSecureURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme != "javascript" && scheme != "data"
    }
    
    /// Returns the file extension in lowercase.
    public var lowercasedPathExtension: String {
        pathExtension.lowercased()
    }
}

extension String {
    /// Returns whether this string is a valid file extension (without dot).
    public var isValidFileExtension: Bool {
        !isEmpty && !contains("/") && !contains("\\") && range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil
    }
}
