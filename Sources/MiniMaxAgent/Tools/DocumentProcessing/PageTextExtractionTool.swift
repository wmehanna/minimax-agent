import Foundation
import PDFKit

/// Represents a single page text extraction result
public struct PageTextResult: Sendable, Equatable {
    /// Path to the source document
    public let path: String
    
    /// Page number (0-indexed)
    public let pageNumber: Int
    
    /// Extracted text content
    public let content: String
    
    /// Whether extraction was successful
    public let success: Bool
    
    /// Error message if extraction failed
    public let error: String?
    
    /// Page dimensions (width, height) in points
    public let pageSize: CGSize?
    
    /// Whether content was truncated
    public let truncated: Bool
    
    public init(
        path: String,
        pageNumber: Int,
        content: String,
        success: Bool,
        error: String? = nil,
        pageSize: CGSize? = nil,
        truncated: Bool = false
    ) {
        self.path = path
        self.pageNumber = pageNumber
        self.content = content
        self.success = success
        self.error = error
        self.pageSize = pageSize
        self.truncated = truncated
    }
}

/// Options for page text extraction
public struct PageTextExtractionOptions: Sendable {
    /// Preserve paragraph structure
    public let preserveParagraphs: Bool
    
    /// Preserve whitespace and indentation
    public let preserveWhitespace: Bool
    
    /// Normalize line endings
    public let normalizeLineEndings: Bool
    
    /// Trim leading/trailing whitespace from each page
    public let trimWhitespace: Bool
    
    /// Include page number in result
    public let includePageNumber: Bool
    
    /// Include page size in result
    public let includePageSize: Bool
    
    /// Maximum characters per page (0 = unlimited)
    public let maxCharacters: Int
    
    public init(
        preserveParagraphs: Bool = true,
        preserveWhitespace: Bool = false,
        normalizeLineEndings: Bool = true,
        trimWhitespace: Bool = true,
        includePageNumber: Bool = true,
        includePageSize: Bool = false,
        maxCharacters: Int = 0
    ) {
        self.preserveParagraphs = preserveParagraphs
        self.preserveWhitespace = preserveWhitespace
        self.normalizeLineEndings = normalizeLineEndings
        self.trimWhitespace = trimWhitespace
        self.includePageNumber = includePageNumber
        self.includePageSize = includePageSize
        self.maxCharacters = maxCharacters
    }
    
    /// Default options
    public static let `default` = PageTextExtractionOptions()
    
    /// Options for extracting plain text
    public static let plainText = PageTextExtractionOptions(
        preserveParagraphs: true,
        preserveWhitespace: false,
        normalizeLineEndings: true,
        trimWhitespace: true,
        includePageNumber: false,
        includePageSize: false,
        maxCharacters: 0
    )
    
    /// Options for extracting with layout preservation
    public static let layoutPreserved = PageTextExtractionOptions(
        preserveParagraphs: true,
        preserveWhitespace: true,
        normalizeLineEndings: true,
        trimWhitespace: false,
        includePageNumber: false,
        includePageSize: true,
        maxCharacters: 0
    )
}

/// Tool for extracting text from specific pages of PDF documents
///
/// Provides focused extraction of text from individual PDF pages with options
/// for controlling text formatting and content limits.
///
/// Phase 3: API Integration — MiniMax API client, Claude API, model management, multimodal
/// Section: 3.4
/// Task: Page text extraction
///
/// Usage:
///
///   let tool = PageTextExtractionTool()
///   
///   // Extract from a single page
///   let result = await tool.extractText(from: "/path/to/document.pdf", page: 0)
///   
///   // Extract from multiple pages
///   let results = await tool.extractText(from: "/path/to/document.pdf", pages: [0, 1, 2])
///   
///   // Extract with custom options
///   let customTool = PageTextExtractionTool(options: .layoutPreserved)
///   let result = await customTool.extractText(from: "/path/to/document.pdf", page: 5)
///
/// Or use the static convenience methods:
///
///   let result = await PageTextExtractionTool.extractText(from: "/path/to.pdf", page: 0)
///   let results = PageTextExtractionTool.extractTextSync(from: "/path/to.pdf", pages: [0, 1])
///
public actor PageTextExtractionTool: Sendable {
    
    /// Configuration options
    public let options: PageTextExtractionOptions
    
    /// Default excluded paths for security
    private static let excludedPathComponents = ["..", "~", "/etc", "/var", "/usr/share"]
    
    public init(options: PageTextExtractionOptions = .default) {
        self.options = options
    }
    
    // MARK: - Public API
    
    /// Extract text from a single page of a document
    /// - Parameters:
    ///   - path: Path to the PDF document
    ///   - page: Page number (0-indexed)
    /// - Returns: PageTextResult containing extracted text
    public func extractText(from path: String, page: Int) async -> PageTextResult {
        guard isPathSafe(path) else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "File not found: \(path)"
            )
        }
        
        let url = URL(fileURLWithPath: path)
        
        guard let document = PDFDocument(url: url) else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Failed to load PDF document"
            )
        }
        
        return extractFromDocument(document, path: path, page: page)
    }
    
    /// Extract text from multiple pages of a document
    /// - Parameters:
    ///   - path: Path to the PDF document
    ///   - pages: Array of page numbers (0-indexed)
    /// - Returns: Array of PageTextResult for each page
    public func extractText(from path: String, pages: [Int]) async -> [PageTextResult] {
        guard isPathSafe(path) else {
            return pages.map { page in
                PageTextResult(
                    path: path,
                    pageNumber: page,
                    content: "",
                    success: false,
                    error: "Path traversal detected: \(path)"
                )
            }
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            return pages.map { page in
                PageTextResult(
                    path: path,
                    pageNumber: page,
                    content: "",
                    success: false,
                    error: "File not found: \(path)"
                )
            }
        }
        
        let url = URL(fileURLWithPath: path)
        
        guard let document = PDFDocument(url: url) else {
            return pages.map { page in
                PageTextResult(
                    path: path,
                    pageNumber: page,
                    content: "",
                    success: false,
                    error: "Failed to load PDF document"
                )
            }
        }
        
        return pages.map { page in
            extractFromDocument(document, path: path, page: page)
        }
    }
    
    /// Extract text from a page range
    /// - Parameters:
    ///   - path: Path to the PDF document
    ///   - range: Range of page numbers (0-indexed, inclusive on both ends)
    /// - Returns: Array of PageTextResult for each page in range
    public func extractText(from path: String, range: Range<Int>) async -> [PageTextResult] {
        let pages = Array(range)
        return await extractText(from: path, pages: pages)
    }
    
    /// Extract text from all pages
    /// - Parameter path: Path to the PDF document
    /// - Returns: Array of PageTextResult for all pages
    public func extractAllPages(from path: String) async -> [PageTextResult] {
        guard isPathSafe(path) else {
            return []
        }
        
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return []
        }
        
        let totalPages = document.pageCount
        let pages = Array(0..<totalPages)
        return await extractText(from: path, pages: pages)
    }
    
    /// Synchronous extraction from multiple pages
    /// - Parameters:
    ///   - path: Path to the PDF document
    ///   - pages: Array of page numbers (0-indexed)
    /// - Returns: Array of PageTextResult for each page
    public func extractTextSync(from path: String, pages: [Int]) -> [PageTextResult] {
        guard isPathSafe(path),
              FileManager.default.fileExists(atPath: path),
              let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return pages.map { page in
                PageTextResult(
                    path: path,
                    pageNumber: page,
                    content: "",
                    success: false,
                    error: "Invalid path or failed to load document"
                )
            }
        }
        
        return pages.map { page in
            extractFromDocumentSync(document, path: path, page: page)
        }
    }
    
    // MARK: - Private Methods
    
    private func extractFromDocument(_ document: PDFDocument, path: String, page: Int) -> PageTextResult {
        let totalPages = document.pageCount
        
        guard page >= 0 && page < totalPages else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Page \(page) out of bounds (document has \(totalPages) pages)"
            )
        }
        
        guard let pdfPage = document.page(at: page) else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Failed to access page \(page)"
            )
        }
        
        return extractTextFromPage(pdfPage, path: path, page: page)
    }
    
    private func extractFromDocumentSync(_ document: PDFDocument, path: String, page: Int) -> PageTextResult {
        let totalPages = document.pageCount
        
        guard page >= 0 && page < totalPages else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Page \(page) out of bounds (document has \(totalPages) pages)"
            )
        }
        
        guard let pdfPage = document.page(at: page) else {
            return PageTextResult(
                path: path,
                pageNumber: page,
                content: "",
                success: false,
                error: "Failed to access page \(page)"
            )
        }
        
        return extractTextFromPage(pdfPage, path: path, page: page)
    }
    
    private func extractTextFromPage(_ page: PDFPage, path: String, page pageIndex: Int) -> PageTextResult {
        let pageSize = page.bounds(for: .mediaBox).size
        
        // Get text selection for the entire page
        let pageRect = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: pageRect) else {
            return PageTextResult(
                path: path,
                pageNumber: pageIndex,
                content: "",
                success: true,
                pageSize: pageSize,
                truncated: false
            )
        }
        
        var text = selection.string ?? ""
        
        if text.isEmpty {
            return PageTextResult(
                path: path,
                pageNumber: pageIndex,
                content: "",
                success: true,
                pageSize: pageSize,
                truncated: false
            )
        }
        
        // Apply text processing based on options
        text = processText(text)
        
        // Check truncation
        let truncated = options.maxCharacters > 0 && text.count > options.maxCharacters
        if truncated {
            text = String(text.prefix(options.maxCharacters))
        }
        
        // Optionally include page number
        let prefix = options.includePageNumber ? "Page \(pageIndex + 1):\n" : ""
        
        return PageTextResult(
            path: path,
            pageNumber: pageIndex,
            content: prefix + text,
            success: true,
            pageSize: options.includePageSize ? pageSize : nil,
            truncated: truncated
        )
    }
    
    private func processText(_ text: String) -> String {
        var result = text
        
        if options.normalizeLineEndings {
            result = result.replacingOccurrences(of: "\r\n", with: "\n")
            result = result.replacingOccurrences(of: "\r", with: "\n")
        }
        
        if options.trimWhitespace {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if options.preserveParagraphs {
            // Normalize multiple blank lines to double newlines
            let pattern = "\\n{3,}"
            result = result.replacingOccurrences(of: pattern, with: "\n\n", options: .regularExpression)
        }
        
        if !options.preserveWhitespace {
            // Collapse multiple spaces to single space
            let pattern = "[ \\t]+"
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            // Collapse multiple newlines
            let newlinePattern = "\\n{2,}"
            result = result.replacingOccurrences(of: newlinePattern, with: "\n", options: .regularExpression)
        }
        
        return result
    }
    
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        
        // Check for path traversal
        if normalized.contains("..") {
            return false
        }
        
        // Check for dangerous path components
        for excluded in Self.excludedPathComponents {
            if normalized.hasPrefix(excluded) {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Static Convenience Methods

extension PageTextExtractionTool {
    
    /// Extract text from a single page (convenience method)
    public static func extractText(from path: String, page: Int) async -> PageTextResult {
        await PageTextExtractionTool().extractText(from: path, page: page)
    }
    
    /// Extract text from multiple pages (convenience method)
    public static func extractText(from path: String, pages: [Int]) async -> [PageTextResult] {
        await PageTextExtractionTool().extractText(from: path, pages: pages)
    }
    
    /// Extract text from a page range (convenience method)
    public static func extractText(from path: String, range: Range<Int>) async -> [PageTextResult] {
        await PageTextExtractionTool().extractText(from: path, range: range)
    }
    
    /// Synchronous extraction from multiple pages (convenience method)
    public static func extractTextSync(from path: String, pages: [Int]) async -> [PageTextResult] {
        await PageTextExtractionTool().extractTextSync(from: path, pages: pages)
    }
    
    /// Extract text from all pages (convenience method)
    public static func extractAllPages(from path: String) async -> [PageTextResult] {
        await PageTextExtractionTool().extractAllPages(from: path)
    }
}
