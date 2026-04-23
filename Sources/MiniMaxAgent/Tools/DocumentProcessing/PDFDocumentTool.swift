import Foundation
import PDFKit

/// Represents a PDF document with its properties and state
public struct PDFDocumentInfo: Sendable, Equatable {
    /// Path to the document (if loaded from file)
    public let path: String?
    
    /// Document URL (if available)
    public let url: URL?
    
    /// Whether the document is valid and loaded
    public let isValid: Bool
    
    /// Number of pages in the document
    public let pageCount: Int
    
    /// Document title from metadata
    public let title: String?
    
    /// Document author from metadata
    public let author: String?
    
    /// Document subject from metadata
    public let subject: String?
    
    /// Document keywords from metadata
    public let keywords: [String]?
    
    /// Creation date from metadata
    public let creationDate: Date?
    
    /// Modification date from metadata
    public let modificationDate: Date?
    
    /// Error message if document failed to load
    public let error: String?
    
    /// Whether document is encrypted
    public let isEncrypted: Bool
    
    /// Whether document allows copying
    public let allowsCopying: Bool
    
    /// Whether document allows printing
    public let allowsPrinting: Bool
    
    public init(
        path: String? = nil,
        url: URL? = nil,
        isValid: Bool = false,
        pageCount: Int = 0,
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        keywords: [String]? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        error: String? = nil,
        isEncrypted: Bool = false,
        allowsCopying: Bool = false,
        allowsPrinting: Bool = false
    ) {
        self.path = path
        self.url = url
        self.isValid = isValid
        self.pageCount = pageCount
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.error = error
        self.isEncrypted = isEncrypted
        self.allowsCopying = allowsCopying
        self.allowsPrinting = allowsPrinting
    }
}

/// Options for PDF document initialization
public struct PDFDocumentOptions: Sendable {
    /// Load document quietly without triggering security callbacks
    public let quiet: Bool
    
    /// Cache document in memory after initial load
    public let cacheInMemory: Bool
    
    /// Validate document structure on load
    public let validateStructure: Bool
    
    /// Maximum page count to load (0 = all pages)
    public let maxPages: Int
    
    public init(
        quiet: Bool = false,
        cacheInMemory: Bool = false,
        validateStructure: Bool = true,
        maxPages: Int = 0
    ) {
        self.quiet = quiet
        self.cacheInMemory = cacheInMemory
        self.validateStructure = validateStructure
        self.maxPages = maxPages
    }
    
    /// Default options
    public static let `default` = PDFDocumentOptions()
    
    /// Quick load options (minimal validation)
    public static let quick = PDFDocumentOptions(
        quiet: true,
        cacheInMemory: false,
        validateStructure: false,
        maxPages: 0
    )
    
    /// Full load options (complete validation)
    public static let full = PDFDocumentOptions(
        quiet: false,
        cacheInMemory: true,
        validateStructure: true,
        maxPages: 0
    )
}

/// Result of PDF document operations
public struct PDFDocumentResult: Sendable, Equatable {
    /// Document information
    public let document: PDFDocumentInfo
    
    /// The underlying PDFDocument (if needed for further operations)
    public let pdfDocument: PDFDocument?
    
    /// Whether the operation was successful
    public var success: Bool { document.isValid && document.error == nil }
    
    public init(document: PDFDocumentInfo, pdfDocument: PDFDocument? = nil) {
        self.document = document
        self.pdfDocument = pdfDocument
    }
}

/// Tool for initializing and working with PDF documents
///
/// Provides a clean API for loading PDF documents from files, URLs, and data
/// with comprehensive error handling and metadata extraction.
///
/// Phase 3: API Integration — MiniMax API client, Claude API, model management, multimodal
/// Section: 3.4
/// Task: PDFDocument initialization
///
/// Usage:
///
///   let tool = PDFDocumentTool()
///   
///   // Load from file path
///   let result = await tool.loadDocument(path: "/path/to/document.pdf")
///   if result.success {
///       print("Loaded: \(result.document.pageCount) pages")
///   }
///   
///   // Load from URL
///   let urlResult = await tool.loadDocument(url: URL(string: "file:///path/to/doc.pdf")!)
///   
///   // Load from data
///   let dataResult = tool.loadDocument(data: pdfData)
///
/// Or use the static convenience methods:
///
///   let result = await PDFDocumentTool.load(path: "/path/to.pdf")
///
public actor PDFDocumentTool: Sendable {
    
    /// Configuration options
    public let options: PDFDocumentOptions
    
    /// Default excluded paths for security
    private static let excludedPathComponents = ["..", "~", "/etc", "/var", "/usr/share"]
    
    public init(options: PDFDocumentOptions = .default) {
        self.options = options
    }
    
    // MARK: - Public API
    
    /// Load a PDF document from a file path
    /// - Parameter path: Path to the PDF file
    /// - Returns: PDFDocumentResult containing document information
    public func loadDocument(path: String) async -> PDFDocumentResult {
        guard isPathSafe(path) else {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    path: path,
                    isValid: false,
                    error: "Path traversal detected: \(path)"
                )
            )
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    path: path,
                    isValid: false,
                    error: "File not found: \(path)"
                )
            )
        }
        
        let url = URL(fileURLWithPath: path)
        return loadDocument(url: url, path: path)
    }
    
    /// Load a PDF document from a URL
    /// - Parameter url: URL to the PDF file
    /// - Returns: PDFDocumentResult containing document information
    public func loadDocument(url: URL) async -> PDFDocumentResult {
        loadDocument(url: url, path: url.path)
    }
    
    /// Load a PDF document from raw data
    /// - Parameter data: PDF file data
    /// - Returns: PDFDocumentResult containing document information
    public func loadDocument(data: Data) -> PDFDocumentResult {
        guard let document = PDFDocument(data: data) else {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    isValid: false,
                    error: "Failed to create PDF document from data"
                )
            )
        }
        
        return createResult(from: document, path: nil)
    }
    
    /// Load a PDF document from a base64 encoded string
    /// - Parameters:
    ///   - base64: Base64 encoded PDF data
    ///   - isURLSafe: Whether the base64 string uses URL-safe encoding
    /// - Returns: PDFDocumentResult containing document information
    public func loadDocument(base64: String, isURLSafe: Bool = false) -> PDFDocumentResult {
        let encoding: Data.Base64DecodingOptions = isURLSafe ? .ignoreUnknownCharacters : []
        
        guard let data = Data(base64Encoded: base64, options: encoding) else {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    isValid: false,
                    error: "Failed to decode base64 string"
                )
            )
        }
        
        return loadDocument(data: data)
    }
    
    /// Check if a file is a valid PDF
    /// - Parameter path: Path to the file
    /// - Returns: true if the file is a valid PDF
    public func isValidPDF(at path: String) -> Bool {
        guard isPathSafe(path),
              FileManager.default.fileExists(atPath: path) else {
            return false
        }
        
        let url = URL(fileURLWithPath: path)
        return PDFDocument(url: url) != nil
    }
    
    /// Get document information without loading full document
    /// - Parameter path: Path to the PDF file
    /// - Returns: PDFDocumentInfo with available metadata
    public func getDocumentInfo(path: String) async -> PDFDocumentInfo {
        guard isPathSafe(path),
              FileManager.default.fileExists(atPath: path) else {
            return PDFDocumentInfo(
                path: path,
                isValid: false,
                error: "File not found: \(path)"
            )
        }
        
        let url = URL(fileURLWithPath: path)
        
        guard let document = PDFDocument(url: url) else {
            return PDFDocumentInfo(
                path: path,
                isValid: false,
                error: "Failed to load PDF document"
            )
        }
        
        return createInfo(from: document, path: path)
    }
    
    // MARK: - Private Methods
    
    private func loadDocument(url: URL, path: String) -> PDFDocumentResult {
        guard let document = PDFDocument(url: url) else {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    path: path,
                    url: url,
                    isValid: false,
                    error: "Failed to load PDF document from URL"
                )
            )
        }
        
        // Validate structure if requested
        if options.validateStructure && document.pageCount == 0 {
            return PDFDocumentResult(
                document: PDFDocumentInfo(
                    path: path,
                    url: url,
                    isValid: false,
                    error: "PDF document has no pages or is corrupted"
                )
            )
        }
        
        return createResult(from: document, path: path)
    }
    
    private func createResult(from document: PDFDocument, path: String?) -> PDFDocumentResult {
        PDFDocumentResult(
            document: createInfo(from: document, path: path),
            pdfDocument: options.cacheInMemory ? document : nil
        )
    }
    
    private func createInfo(from document: PDFDocument, path: String?) -> PDFDocumentInfo {
        let attributes = document.documentAttributes ?? [:]
        
        // Check document permissions
        let isEncrypted = document.isEncrypted
        let allowsCopying = document.allowsCopying
        let allowsPrinting = document.allowsPrinting
        
        return PDFDocumentInfo(
            path: path,
            url: document.documentURL,
            isValid: true,
            pageCount: document.pageCount,
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String,
            keywords: attributes[PDFDocumentAttribute.keywordsAttribute] as? [String],
            creationDate: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date,
            modificationDate: attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date,
            isEncrypted: isEncrypted,
            allowsCopying: allowsCopying,
            allowsPrinting: allowsPrinting
        )
    }
    
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        
        if normalized.contains("..") {
            return false
        }
        
        for excluded in Self.excludedPathComponents {
            if normalized.hasPrefix(excluded) {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Static Convenience Methods

extension PDFDocumentTool {
    
    /// Load a PDF document from a file path
    public static func load(path: String) async -> PDFDocumentResult {
        await PDFDocumentTool().loadDocument(path: path)
    }
    
    /// Load a PDF document from a URL
    public static func load(url: URL) async -> PDFDocumentResult {
        await PDFDocumentTool().loadDocument(url: url)
    }
    
    /// Load a PDF document from raw data
    public static func load(data: Data) async -> PDFDocumentResult {
        await PDFDocumentTool().loadDocument(data: data)
    }
    
    /// Load a PDF document from a base64 encoded string
    public static func load(base64: String, isURLSafe: Bool = false) async -> PDFDocumentResult {
        await PDFDocumentTool().loadDocument(base64: base64, isURLSafe: isURLSafe)
    }
    
    /// Check if a file is a valid PDF
    public static func isValid(path: String) async -> Bool {
        await PDFDocumentTool().isValidPDF(at: path)
    }
    
    /// Get document information
    public static func info(path: String) async -> PDFDocumentInfo {
        await PDFDocumentTool().getDocumentInfo(path: path)
    }
}
