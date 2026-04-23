import Foundation
import Markdown

/// Options for markdown rendering
public struct MarkdownOptions: Sendable {
    /// Whether to parse with smart quotes/dashes disabled
    public let disableSmartOpts: Bool

    /// Maximum heading level to render (0 = unlimited)
    public let maxHeadingLevel: Int

    public init(
        disableSmartOpts: Bool = false,
        maxHeadingLevel: Int = 0
    ) {
        self.disableSmartOpts = disableSmartOpts
        self.maxHeadingLevel = maxHeadingLevel
    }

    /// Default options
    public static let `default` = MarkdownOptions()
}

/// Result of markdown parsing
public struct MarkdownParseResult: Sendable {
    /// The raw markdown source text
    public let source: String

    /// Summary of document structure
    public let structure: DocumentStructure

    /// Any parsing warnings or issues
    public let warnings: [String]

    public init(source: String, structure: DocumentStructure, warnings: [String] = []) {
        self.source = source
        self.structure = structure
        self.warnings = warnings
    }
}

/// Structure summary of a markdown document
public struct DocumentStructure: Sendable, Equatable {
    /// Number of headings in the document
    public let headingCount: Int

    /// Heading levels found (e.g., [1, 2, 2, 3] for # ## ## ###)
    public let headingLevels: [Int]

    /// Number of code blocks
    public let codeBlockCount: Int

    /// Number of links
    public let linkCount: Int

    /// Number of images
    public let imageCount: Int

    /// Number of unordered lists
    public let unorderedListCount: Int

    /// Number of ordered lists
    public let orderedListCount: Int

    /// Number of tables
    public let tableCount: Int

    /// Number of paragraphs
    public let paragraphCount: Int

    /// Whether document has frontmatter
    public let hasFrontMatter: Bool

    /// Estimated word count
    public let wordCount: Int

    public init(
        headingCount: Int = 0,
        headingLevels: [Int] = [],
        codeBlockCount: Int = 0,
        linkCount: Int = 0,
        imageCount: Int = 0,
        unorderedListCount: Int = 0,
        orderedListCount: Int = 0,
        tableCount: Int = 0,
        paragraphCount: Int = 0,
        hasFrontMatter: Bool = false,
        wordCount: Int = 0
    ) {
        self.headingCount = headingCount
        self.headingLevels = headingLevels
        self.codeBlockCount = codeBlockCount
        self.linkCount = linkCount
        self.imageCount = imageCount
        self.unorderedListCount = unorderedListCount
        self.orderedListCount = orderedListCount
        self.tableCount = tableCount
        self.paragraphCount = paragraphCount
        self.hasFrontMatter = hasFrontMatter
        self.wordCount = wordCount
    }
}

/// Markdown rendering tool using Apple's swift-markdown library
///
/// Provides markdown parsing, analysis, and rendering capabilities.
/// Supports standard CommonMark plus GitHub-flavored markdown extensions.
///
/// Phase 1: Project Setup & Shell — swift-markdown integration
///
/// Usage:
///   let tool = MarkdownTool()
///   let result = tool.parse(markdown: "# Hello\n\nThis is **bold** text.")
///   print(result.structure.headingCount) // 1
public struct MarkdownTool: Sendable {

    public let options: MarkdownOptions

    public init(options: MarkdownOptions = .default) {
        self.options = options
    }

    // MARK: - Public API

    /// Parse markdown text and return analysis results
    /// - Parameter markdown: The markdown source text to parse
    /// - Returns: MarkdownParseResult containing document structure and source
    public func parse(markdown: String) -> MarkdownParseResult {
        var warnings: [String] = []

        // Configure parse options
        var parseOptions = Markdown.ParseOptions()
        if options.disableSmartOpts {
            parseOptions.insert(.disableSmartOpts)
        }

        // Parse the markdown
        let document = Document(parsing: markdown, options: parseOptions)

        // Analyze structure
        let structure = analyzeStructure(document: document, source: markdown)

        // Check for issues
        if markdown.isEmpty {
            warnings.append("Empty markdown input")
        }

        return MarkdownParseResult(
            source: markdown,
            structure: structure,
            warnings: warnings
        )
    }

    /// Quick parse with just markdown string (uses default options)
    public static func parse(_ markdown: String) -> MarkdownParseResult {
        MarkdownTool().parse(markdown: markdown)
    }

    /// Extract plain text from markdown (strips formatting)
    /// - Parameter markdown: The markdown source text
    /// - Returns: Plain text with formatting removed
    public func extractPlainText(markdown: String) -> String {
        let document = Document(parsing: markdown)

        var plainText = ""
        for child in document.children {
            plainText.append(extractPlainText(from: child))
            plainText.append("\n")
        }

        return plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract all headings from markdown
    /// - Parameter markdown: The markdown source text
    /// - Returns: Array of tuples containing heading level and text
    public func extractHeadings(markdown: String) -> [(level: Int, text: String)] {
        let document = Document(parsing: markdown)
        var headings: [(level: Int, text: String)] = []

        for child in document.children {
            gatherHeadings(from: child, into: &headings)
        }

        return headings
    }

    /// Extract all code blocks from markdown
    /// - Parameter markdown: The markdown source text
    /// - Returns: Array of code block info (language and code)
    public func extractCodeBlocks(markdown: String) -> [(language: String?, code: String)] {
        let document = Document(parsing: markdown)
        var codeBlocks: [(language: String?, code: String)] = []

        for child in document.children {
            gatherCodeBlocks(from: child, into: &codeBlocks)
        }

        return codeBlocks
    }

    /// Extract all links from markdown
    /// - Parameter markdown: The markdown source text
    /// - Returns: Array of tuples containing URL and title
    public func extractLinks(markdown: String) -> [(title: String?, url: String)] {
        let document = Document(parsing: markdown)
        var links: [(title: String?, url: String)] = []

        for child in document.children {
            extractLinks(from: child, into: &links)
        }

        return links
    }

    /// Validate markdown syntax
    /// - Parameter markdown: The markdown source text
    /// - Returns: Validation result with any errors found
    public func validate(markdown: String) -> MarkdownValidationResult {
        var errors: [MarkdownValidationError] = []

        // Check for unclosed code blocks
        if markdown.components(separatedBy: "```").count % 2 != 0 && markdown.contains("```") {
            errors.append(MarkdownValidationError(
                line: nil,
                column: nil,
                message: "Unclosed code block",
                severity: .error
            ))
        }

        // Check for unbalanced emphasis
        let boldCount = markdown.components(separatedBy: "**").count - 1
        if boldCount % 2 != 0 {
            errors.append(MarkdownValidationError(
                line: nil,
                column: nil,
                message: "Unbalanced bold markers (**)",
                severity: .error
            ))
        }

        // Check for unbalanced backticks
        let backtickCount = markdown.filter { $0 == "`" }.count
        if backtickCount % 2 != 0 {
            errors.append(MarkdownValidationError(
                line: nil,
                column: nil,
                message: "Unbalanced backticks (`)",
                severity: .error
            ))
        }

        // Check for invalid link syntax
        let linkPattern = try? NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(([^)]*)\\)", options: [])
        let range = NSRange(markdown.startIndex..., in: markdown)
        linkPattern?.enumerateMatches(in: markdown, options: [], range: range) { match, _, _ in
            if let match = match {
                let urlRange = Range(match.range(at: 2), in: markdown)!
                let url = String(markdown[urlRange])
                if !url.isEmpty && !url.hasPrefix("http") && !url.hasPrefix("/") && !url.hasPrefix("#") {
                    errors.append(MarkdownValidationError(
                        line: nil,
                        column: nil,
                        message: "Invalid link URL: \(url)",
                        severity: .warning
                    ))
                }
            }
        }

        return MarkdownValidationResult(isValid: errors.isEmpty, errors: errors)
    }

    // MARK: - Private Methods

    private func analyzeStructure(document: Document, source: String) -> DocumentStructure {
        var headingCount = 0
        var headingLevels: [Int] = []
        var codeBlockCount = 0
        var linkCount = 0
        var imageCount = 0
        var unorderedListCount = 0
        var orderedListCount = 0
        var tableCount = 0
        var paragraphCount = 0
        var hasFrontMatter = false
        var wordCount = 0

        // Check for frontmatter
        if source.hasPrefix("---") || source.hasPrefix("...") {
            hasFrontMatter = true
        }

        // Count words
        wordCount = source.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        for child in document.children {
            let result = analyzeMarkup(child)
            headingCount += result.headingCount
            headingLevels.append(contentsOf: result.headingLevels)
            codeBlockCount += result.codeBlockCount
            linkCount += result.linkCount
            imageCount += result.imageCount
            unorderedListCount += result.unorderedListCount
            orderedListCount += result.orderedListCount
            tableCount += result.tableCount
            paragraphCount += result.paragraphCount
        }

        return DocumentStructure(
            headingCount: headingCount,
            headingLevels: headingLevels,
            codeBlockCount: codeBlockCount,
            linkCount: linkCount,
            imageCount: imageCount,
            unorderedListCount: unorderedListCount,
            orderedListCount: orderedListCount,
            tableCount: tableCount,
            paragraphCount: paragraphCount,
            hasFrontMatter: hasFrontMatter,
            wordCount: wordCount
        )
    }

    private func analyzeMarkup(_ markup: Markup) -> (headingCount: Int, headingLevels: [Int], codeBlockCount: Int, linkCount: Int, imageCount: Int, unorderedListCount: Int, orderedListCount: Int, tableCount: Int, paragraphCount: Int) {
        var headingCount = 0
        var headingLevels: [Int] = []
        var codeBlockCount = 0
        var linkCount = 0
        var imageCount = 0
        var unorderedListCount = 0
        var orderedListCount = 0
        var tableCount = 0
        var paragraphCount = 0

        switch markup {
        case is Markdown.Heading:
            headingCount = 1
            if let heading = markup as? Markdown.Heading {
                headingLevels = [heading.level]
            }
        case is CodeBlock:
            codeBlockCount = 1
        case is Markdown.Link:
            linkCount = 1
        case is Markdown.Image:
            imageCount = 1
        case is UnorderedList:
            unorderedListCount = 1
        case is OrderedList:
            orderedListCount = 1
        case is Table:
            tableCount = 1
        case is Paragraph:
            paragraphCount = 1
        default:
            break
        }

        for child in markup.children {
            let childResult = analyzeMarkup(child)
            headingCount += childResult.headingCount
            headingLevels.append(contentsOf: childResult.headingLevels)
            codeBlockCount += childResult.codeBlockCount
            linkCount += childResult.linkCount
            imageCount += childResult.imageCount
            unorderedListCount += childResult.unorderedListCount
            orderedListCount += childResult.orderedListCount
            tableCount += childResult.tableCount
            paragraphCount += childResult.paragraphCount
        }

        return (headingCount, headingLevels, codeBlockCount, linkCount, imageCount, unorderedListCount, orderedListCount, tableCount, paragraphCount)
    }

    private func gatherHeadings(from markup: Markup, into headings: inout [(level: Int, text: String)]) {
        if let heading = markup as? Markdown.Heading {
            let level = heading.level
            let text = extractPlainText(from: heading)
            headings.append((level: level, text: text))
        }

        for child in markup.children {
            gatherHeadings(from: child, into: &headings)
        }
    }

    private func gatherCodeBlocks(from markup: Markup, into codeBlocks: inout [(language: String?, code: String)]) {
        if let codeBlock = markup as? CodeBlock {
            codeBlocks.append((language: codeBlock.language, code: codeBlock.code))
        }

        for child in markup.children {
            gatherCodeBlocks(from: child, into: &codeBlocks)
        }
    }

    private func extractPlainText(from block: Markup) -> String {
        var text = ""

        for child in block.children {
            if let textChild = child as? Text {
                text.append(textChild.string)
            } else if let emph = child as? Strong {
                text.append(extractPlainText(from: emph))
            } else if let link = child as? Markdown.Link {
                text.append(link.title ?? link.destination ?? "")
            } else if let image = child as? Markdown.Image {
                text.append(image.title ?? "")
            } else if child is SoftBreak {
                text.append(" ")
            } else if child is LineBreak {
                text.append("\n")
            } else {
                text.append(extractPlainText(from: child))
            }
        }

        return text
    }

    private func extractLinks(from block: Markup, into links: inout [(title: String?, url: String)]) {
        for child in block.children {
            if let link = child as? Markdown.Link {
                links.append((title: link.title, url: link.destination ?? ""))
            }
            extractLinks(from: child, into: &links)
        }
    }
}

// MARK: - Supporting Types

/// Result of markdown validation
public struct MarkdownValidationResult: Sendable, Equatable {
    /// Whether the markdown is valid
    public let isValid: Bool

    /// Any validation errors found
    public let errors: [MarkdownValidationError]

    public init(isValid: Bool, errors: [MarkdownValidationError]) {
        self.isValid = isValid
        self.errors = errors
    }
}

/// A single validation error
public struct MarkdownValidationError: Sendable, Equatable {
    /// Line number where error occurred (nil if not applicable)
    public let line: Int?

    /// Column number where error occurred (nil if not applicable)
    public let column: Int?

    /// Error message
    public let message: String

    /// Error severity
    public let severity: Severity

    public init(line: Int?, column: Int?, message: String, severity: Severity) {
        self.line = line
        self.column = column
        self.message = message
        self.severity = severity
    }

    public enum Severity: String, Sendable {
        case error
        case warning
        case info
    }
}
