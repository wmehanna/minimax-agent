import Foundation
import PDFKit

/// Tool for extracting text from documents while preserving layout
public actor TextLayoutPreservationTool {
    
    /// Configuration for text layout extraction
    public struct Config: Sendable {
        /// Preserve paragraph breaks
        public let preserveParagraphs: Bool
        
        /// Preserve whitespace and indentation
        public let preserveWhitespace: Bool
        
        /// Preserve table structure
        public let preserveTables: Bool
        
        /// Preserve heading hierarchy
        public let preserveHeadings: Bool
        
        /// Maximum pages to process (0 = all)
        public let maxPages: Int
        
        /// Starting page (0-indexed, 0 = first page)
        public let startPage: Int
        
        public init(
            preserveParagraphs: Bool = true,
            preserveWhitespace: Bool = true,
            preserveTables: Bool = true,
            preserveHeadings: Bool = true,
            maxPages: Int = 0,
            startPage: Int = 0
        ) {
            self.preserveParagraphs = preserveParagraphs
            self.preserveWhitespace = preserveWhitespace
            self.preserveTables = preserveTables
            self.preserveHeadings = preserveHeadings
            self.maxPages = maxPages
            self.startPage = startPage
        }
    }
    
    /// Result of text layout extraction
    public struct LayoutResult: Sendable, Equatable {
        /// Path that was processed
        public let path: String
        
        /// Extracted text with layout preserved
        public let content: String
        
        /// Whether extraction was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// Number of pages processed
        public let pagesProcessed: Int
        
        /// Total pages in document
        public let totalPages: Int
        
        /// Whether content was truncated
        public let truncated: Bool
        
        /// Document metadata
        public let metadata: DocumentMetadata?
        
        public init(
            path: String,
            content: String,
            success: Bool,
            error: String? = nil,
            pagesProcessed: Int = 0,
            totalPages: Int = 0,
            truncated: Bool = false,
            metadata: DocumentMetadata? = nil
        ) {
            self.path = path
            self.content = content
            self.success = success
            self.error = error
            self.pagesProcessed = pagesProcessed
            self.totalPages = totalPages
            self.truncated = truncated
            self.metadata = metadata
        }
    }
    
    /// Document metadata
    public struct DocumentMetadata: Sendable, Equatable, Codable {
        /// Document title
        public let title: String?
        
        /// Document author
        public let author: String?
        
        /// Creation date
        public let creationDate: Date?
        
        /// Modification date
        public let modificationDate: Date?
        
        /// Document subject
        public let subject: String?
        
        /// Keywords
        public let keywords: [String]?
        
        public init(
            title: String? = nil,
            author: String? = nil,
            creationDate: Date? = nil,
            modificationDate: Date? = nil,
            subject: String? = nil,
            keywords: [String]? = nil
        ) {
            self.title = title
            self.author = author
            self.creationDate = creationDate
            self.modificationDate = modificationDate
            self.subject = subject
            self.keywords = keywords
        }
    }
    
    /// Layout block types
    public enum LayoutBlockType: String, Sendable, Codable {
        case paragraph
        case heading1
        case heading2
        case heading3
        case heading4
        case heading5
        case heading6
        case table
        case tableRow
        case tableCell
        case listItem
        case blockQuote
        case codeBlock
        case pageBreak
    }
    
    /// A block of text with layout information
    public struct LayoutBlock: Sendable, Equatable, Codable {
        /// Type of layout block
        public let type: LayoutBlockType
        
        /// Text content
        public let content: String
        
        /// Indentation level (for nested structures)
        public let indentation: Int
        
        /// Starting line number
        public let lineNumber: Int
        
        /// Font size (if available)
        public let fontSize: CGFloat?
        
        /// Font weight (if available)
        public let fontWeight: String?
        
        /// Whether text is bold
        public let isBold: Bool
        
        /// Whether text is italic
        public let isItalic: Bool
        
        public init(
            type: LayoutBlockType,
            content: String,
            indentation: Int = 0,
            lineNumber: Int = 0,
            fontSize: CGFloat? = nil,
            fontWeight: String? = nil,
            isBold: Bool = false,
            isItalic: Bool = false
        ) {
            self.type = type
            self.content = content
            self.indentation = indentation
            self.lineNumber = lineNumber
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.isBold = isBold
            self.isItalic = isItalic
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Extract text from a document with layout preservation
    public func extract(path: String) async -> LayoutResult {
        // Security check
        guard isPathSafe(path) else {
            return LayoutResult(
                path: path,
                content: "",
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            return LayoutResult(
                path: path,
                content: "",
                success: false,
                error: "File not found: \(path)"
            )
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Determine file type
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            return await extractFromPDF(url: url)
        case "txt", "text":
            return await extractFromText(url: url)
        default:
            return LayoutResult(
                path: path,
                content: "",
                success: false,
                error: "Unsupported file type: \(fileExtension)"
            )
        }
    }
    
    /// Extract text from PDF with layout preservation
    private func extractFromPDF(url: URL) async -> LayoutResult {
        guard let document = PDFDocument(url: url) else {
            return LayoutResult(
                path: url.path,
                content: "",
                success: false,
                error: "Failed to load PDF document"
            )
        }
        
        let totalPages = document.pageCount
        let startPage = config.startPage
        let endPage = config.maxPages > 0 
            ? min(startPage + config.maxPages, totalPages) 
            : totalPages
        
        var allContent: [String] = []
        var pagesProcessed = 0
        
        for pageIndex in startPage..<endPage {
            guard let page = document.page(at: pageIndex) else { continue }
            
            let pageContent = extractTextFromPage(page, pageIndex: pageIndex)
            if !pageContent.isEmpty {
                allContent.append(pageContent)
                pagesProcessed += 1
            }
        }
        
        let content = allContent.joined(separator: "\n\n")
        let metadata = extractMetadata(from: document)
        
        return LayoutResult(
            path: url.path,
            content: content,
            success: true,
            pagesProcessed: pagesProcessed,
            totalPages: totalPages,
            truncated: config.maxPages > 0 && endPage < totalPages,
            metadata: metadata
        )
    }
    
    /// Extract text from a single PDF page with layout preservation
    private func extractTextFromPage(_ page: PDFPage, pageIndex: Int) -> String {
        var lines: [String] = []
        
        // Get page dimensions
        let pageRect = page.bounds(for: .mediaBox)
        
        // Use selection to get text with layout
        guard let selection = page.selection(for: NSRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)) else {
            return ""
        }
        
        guard let string = selection.string else {
            return ""
        }
        
        if config.preserveParagraphs {
            // Split by paragraph while preserving structure
            let paragraphs = string.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            lines = paragraphs
        } else {
            lines = string.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        
        if config.preserveWhitespace {
            // Preserve indentation by analyzing leading whitespace
            lines = lines.map { line in
                let leadingSpaces = line.prefix(while: { $0 == " " })
                let indentation = leadingSpaces.count / 4  // Assume 4 spaces = 1 indent level
                return String(repeating: "  ", count: indentation) + line.trimmingCharacters(in: .whitespaces)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Extract text from plain text file with layout preservation
    private func extractFromText(url: URL) async -> LayoutResult {
        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            
            if !config.preserveWhitespace {
                // Collapse multiple spaces
                let pattern = "\\s+"
                content = content.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            
            if !config.preserveParagraphs {
                // Remove extra blank lines
                let pattern = "\\n\\s*\\n+"
                content = content.replacingOccurrences(of: pattern, with: "\n\n", options: .regularExpression)
            }
            
            return LayoutResult(
                path: url.path,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                success: true,
                pagesProcessed: 1,
                totalPages: 1
            )
        } catch {
            return LayoutResult(
                path: url.path,
                content: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Extract metadata from PDF document
    private func extractMetadata(from document: PDFDocument) -> DocumentMetadata {
        let attributes = document.documentAttributes ?? [:]
        
        return DocumentMetadata(
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            creationDate: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date,
            modificationDate: attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String,
            keywords: (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String])
        )
    }
    
    /// Check if path is safe
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
}

/// Options for text layout extraction
public struct TextLayoutOptions: Sendable {
    /// Preserve paragraph breaks
    public let preserveParagraphs: Bool
    
    /// Preserve whitespace and indentation
    public let preserveWhitespace: Bool
    
    /// Preserve table structure
    public let preserveTables: Bool
    
    /// Preserve heading hierarchy
    public let preserveHeadings: Bool
    
    /// Maximum pages to process (0 = all)
    public let maxPages: Int
    
    /// Starting page (0-indexed)
    public let startPage: Int
    
    public init(
        preserveParagraphs: Bool = true,
        preserveWhitespace: Bool = true,
        preserveTables: Bool = true,
        preserveHeadings: Bool = true,
        maxPages: Int = 0,
        startPage: Int = 0
    ) {
        self.preserveParagraphs = preserveParagraphs
        self.preserveWhitespace = preserveWhitespace
        self.preserveTables = preserveTables
        self.preserveHeadings = preserveHeadings
        self.maxPages = maxPages
        self.startPage = startPage
    }
}
