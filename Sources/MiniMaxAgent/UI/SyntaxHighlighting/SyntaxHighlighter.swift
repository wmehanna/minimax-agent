import SwiftUI
import Foundation

/// A lightweight syntax highlighter using AttributedString and regex-based tokenization.
/// Supports multiple languages without external dependencies.
public struct SyntaxHighlighter {

    // MARK: - Supported Languages

    /// Supported programming languages for syntax highlighting
    public enum Language: String, CaseIterable, Sendable {
        case swift
        case python
        case javascript
        case typescript
        case bash
        case shell
        case json
        case yaml
        case xml
        case markdown
        case c
        case cpp
        case objectivec
        case java
        case kotlin
        case go
        case rust
        case ruby
        case php
        case sql
        case html
        case css
        case plaintext

        public var displayName: String {
            switch self {
            case .swift: return "Swift"
            case .python: return "Python"
            case .javascript: return "JavaScript"
            case .typescript: return "TypeScript"
            case .bash: return "Bash"
            case .shell: return "Shell"
            case .json: return "JSON"
            case .yaml: return "YAML"
            case .xml: return "XML"
            case .markdown: return "Markdown"
            case .c: return "C"
            case .cpp: return "C++"
            case .objectivec: return "Objective-C"
            case .java: return "Java"
            case .kotlin: return "Kotlin"
            case .go: return "Go"
            case .rust: return "Rust"
            case .ruby: return "Ruby"
            case .php: return "PHP"
            case .sql: return "SQL"
            case .html: return "HTML"
            case .css: return "CSS"
            case .plaintext: return "Plain Text"
            }
        }
    }

    // MARK: - Theme

    /// Color theme for syntax highlighting
    public struct Theme: Sendable {
        public let keyword: Color
        public let string: Color
        public let number: Color
        public let comment: Color
        public let type: Color
        public let function: Color
        public let property: Color
        public let operator_: Color
        public let punctuation: Color
        public let plain: Color

        public init(
            keyword: Color = Color(red: 0.93, green: 0.27, blue: 0.53),
            string: Color = Color(red: 0.75, green: 0.41, blue: 0.22),
            number: Color = Color(red: 0.11, green: 0.71, blue: 0.55),
            comment: Color = Color(red: 0.44, green: 0.47, blue: 0.51),
            type: Color = Color(red: 0.13, green: 0.59, blue: 0.95),
            function: Color = Color(red: 0.20, green: 0.44, blue: 0.85),
            property: Color = Color(red: 0.60, green: 0.60, blue: 0.60),
            operator_: Color = Color(red: 0.85, green: 0.85, blue: 0.85),
            punctuation: Color = Color(red: 0.80, green: 0.80, blue: 0.80),
            plain: Color = Color.primary
        ) {
            self.keyword = keyword
            self.string = string
            self.number = number
            self.comment = comment
            self.type = type
            self.function = function
            self.property = property
            self.operator_ = operator_
            self.punctuation = punctuation
            self.plain = plain
        }

        /// Xcode Light theme
        public static let xcodeLight = Theme()

        /// Xcode Dark theme (based on Xcode Dark)
        public static let xcodeDark = Theme(
            keyword: Color(red: 1.0, green: 0.43, blue: 0.67),
            string: Color(red: 1.0, green: 0.82, blue: 0.57),
            number: Color(red: 0.68, green: 0.90, blue: 0.80),
            comment: Color(red: 0.53, green: 0.63, blue: 0.67),
            type: Color(red: 0.50, green: 0.78, blue: 1.0),
            function: Color(red: 0.87, green: 0.76, blue: 1.0),
            property: Color(red: 0.80, green: 0.80, blue: 0.80),
            operator_: Color(red: 0.90, green: 0.90, blue: 0.90),
            punctuation: Color(red: 0.90, green: 0.90, blue: 0.90),
            plain: Color(red: 0.89, green: 0.89, blue: 0.89)
        )

        /// Monokai-inspired theme
        public static let monokai = Theme(
            keyword: Color(red: 0.93, green: 0.27, blue: 0.53),
            string: Color(red: 0.75, green: 0.41, blue: 0.22),
            number: Color(red: 0.11, green: 0.71, blue: 0.55),
            comment: Color(red: 0.53, green: 0.63, blue: 0.67),
            type: Color(red: 0.13, green: 0.59, blue: 0.95),
            function: Color(red: 0.20, green: 0.44, blue: 0.85),
            property: Color(red: 0.60, green: 0.60, blue: 0.60),
            operator_: Color(red: 0.85, green: 0.85, blue: 0.85),
            punctuation: Color(red: 0.80, green: 0.80, blue: 0.80),
            plain: Color.primary
        )
    }

    // MARK: - Token

    /// A syntax token with a range and type
    private struct Token: Identifiable {
        let id = UUID()
        let range: Range<String.Index>
        let type: TokenType
    }

    private enum TokenType {
        case keyword
        case string
        case number
        case comment
        case type
        case function
        case property
        case `operator`
        case punctuation
    }

    // MARK: - Properties

    private let theme: Theme

    // MARK: - Initialization

    public init(theme: Theme = .xcodeLight) {
        self.theme = theme
    }

    // MARK: - Public Methods

    /// Highlight a string and return an AttributedString
    /// - Parameters:
    ///   - code: The code string to highlight
    ///   - language: The programming language
    /// - Returns: An AttributedString with syntax highlighting applied
    public func highlight(_ code: String, language: Language) -> AttributedString {
        var attributedString = AttributedString(code)
        attributedString.foregroundColor = theme.plain
        attributedString.font = .body.monospaced()

        let tokens = tokenize(code, language: language)

        for token in tokens {
            guard let attrRange = Range(token.range, in: attributedString) else { continue }

            let color: Color
            switch token.type {
            case .keyword: color = theme.keyword
            case .string: color = theme.string
            case .number: color = theme.number
            case .comment: color = theme.comment
            case .type: color = theme.type
            case .function: color = theme.function
            case .property: color = theme.property
            case .operator: color = theme.operator_
            case .punctuation: color = theme.punctuation
            }

            attributedString[attrRange].foregroundColor = color
        }

        return attributedString
    }

    /// Highlight a string and return an NSAttributedString (for NSTextView, etc.)
    /// - Parameters:
    ///   - code: The code string to highlight
    ///   - language: The programming language
    /// - Returns: An NSAttributedString with syntax highlighting applied
    public func highlightNS(_ code: String, language: Language) -> NSAttributedString {
        let attributedString = highlight(code, language: language)
        return NSAttributedString(attributedString)
    }

    // MARK: - Tokenization

    private func tokenize(_ code: String, language: Language) -> [Token] {
        var tokens: [Token] = []

        // Tokenize comments first (they take precedence)
        tokens.append(contentsOf: tokenizeComments(code, language: language))

        // Tokenize strings (they take precedence over other patterns)
        tokens.append(contentsOf: tokenizeStrings(code))

        // Tokenize based on language
        switch language {
        case .swift:
            tokens.append(contentsOf: tokenizeSwift(code))
        case .python:
            tokens.append(contentsOf: tokenizePython(code))
        case .javascript, .typescript:
            tokens.append(contentsOf: tokenizeJavaScript(code))
        case .bash, .shell:
            tokens.append(contentsOf: tokenizeShell(code))
        case .json:
            tokens.append(contentsOf: tokenizeJSON(code))
        case .yaml:
            tokens.append(contentsOf: tokenizeYAML(code))
        case .c, .cpp, .objectivec:
            tokens.append(contentsOf: tokenizeCFamily(code))
        case .java, .kotlin:
            tokens.append(contentsOf: tokenizeJava(code))
        case .go:
            tokens.append(contentsOf: tokenizeGo(code))
        case .rust:
            tokens.append(contentsOf: tokenizeRust(code))
        case .sql:
            tokens.append(contentsOf: tokenizeSQL(code))
        case .html, .xml:
            tokens.append(contentsOf: tokenizeHTML(code))
        case .css:
            tokens.append(contentsOf: tokenizeCSS(code))
        case .markdown:
            tokens.append(contentsOf: tokenizeMarkdown(code))
        case .plaintext:
            break
        default:
            tokens.append(contentsOf: tokenizeGeneric(code))
        }

        return tokens
    }

    // MARK: - Comment Tokenization

    private func tokenizeComments(_ code: String, language: Language) -> [Token] {
        var tokens: [Token] = []

        switch language {
        case .html, .xml, .markdown:
            // HTML-style comments: <!-- ... -->
            if let regex = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .comment))
                    }
                }
            }
        default:
            // Single-line comments: // ...
            if let regex = try? NSRegularExpression(pattern: "//[^\n]*") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .comment))
                    }
                }
            }

            // Multi-line comments: /* ... */
            if let regex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .comment))
                    }
                }
            }

            // Python-style comments: # ...
            if let regex = try? NSRegularExpression(pattern: "#[^\n]*") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .comment))
                    }
                }
            }

            // Shell comments: # ...
            if let regex = try? NSRegularExpression(pattern: "#[^\n]*") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .comment))
                    }
                }
            }
        }

        return tokens
    }

    // MARK: - String Tokenization

    private func tokenizeStrings(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Double-quoted strings (escaping handled)
        if let regex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .string))
                }
            }
        }

        // Single-quoted strings
        if let regex = try? NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .string))
                }
            }
        }

        // Template literals (backtick strings)
        if let regex = try? NSRegularExpression(pattern: "`(?:[^`\\\\]|\\\\.)*`") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .string))
                }
            }
        }

        return tokens
    }

    // MARK: - Swift Tokenization

    private func tokenizeSwift(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Keywords
        let keywords = [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension",
            "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard", "if",
            "import", "in", "indirect", "infix", "init", "inout", "internal", "is", "isolated",
            "lazy", "let", "mutating", "nil", "nonisolated", "nonmutating", "open", "operator",
            "optional", "override", "postfix", "precedencegroup", "prefix", "private", "protocol",
            "public", "repeat", "required", "rethrows", "return", "self", "Self", "set", "some",
            "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
            "typealias", "unowned", "var", "weak", "where", "while", "willSet", "didSet"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Types (capitalized words)
        if let regex = try? NSRegularExpression(pattern: "\\b[A-Z][a-zA-Z0-9_]*\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .type))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Functions (identifier followed by parenthesis)
        if let regex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if match.numberOfRanges > 1, let fnRange = Range(match.range(at: 1), in: code) {
                    tokens.append(Token(range: fnRange, type: .function))
                }
            }
        }

        return tokens
    }

    // MARK: - Python Tokenization

    private func tokenizePython(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "False", "None", "True", "and", "as", "assert", "async", "await",
            "break", "class", "continue", "def", "del", "elif", "else", "except",
            "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
            "while", "with", "yield"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Decorators
        if let regex = try? NSRegularExpression(pattern: "@[a-zA-Z_][a-zA-Z0-9_]*") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .keyword))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Classes (capitalized words)
        if let regex = try? NSRegularExpression(pattern: "\\b[A-Z][a-zA-Z0-9_]*\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .type))
                }
            }
        }

        // Functions
        if let regex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if match.numberOfRanges > 1, let fnRange = Range(match.range(at: 1), in: code) {
                    tokens.append(Token(range: fnRange, type: .function))
                }
            }
        }

        return tokens
    }

    // MARK: - JavaScript/TypeScript Tokenization

    private func tokenizeJavaScript(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "export", "extends", "false",
            "finally", "for", "function", "if", "import", "in", "instanceof", "let",
            "new", "null", "return", "static", "super", "switch", "this", "throw",
            "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Functions
        if let regex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_$][a-zA-Z0-9_$]*)\\s*\\(") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if match.numberOfRanges > 1, let fnRange = Range(match.range(at: 1), in: code) {
                    tokens.append(Token(range: fnRange, type: .function))
                }
            }
        }

        return tokens
    }

    // MARK: - Shell/Bash Tokenization

    private func tokenizeShell(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "select",
            "while", "until", "do", "done", "in", "function", "time", "coproc",
            "export", "readonly", "local", "declare", "typeset", "unset", "shift",
            "return", "exit", "break", "continue", "source", "alias", "unalias",
            "set", "shopt", "trap", "eval", "exec"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Variables
        if let regex = try? NSRegularExpression(pattern: "\\$[a-zA-Z_][a-zA-Z0-9_]*") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - JSON Tokenization

    private func tokenizeJSON(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Keys (string followed by colon)
        if let regex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"\\s*:") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                let keyRange = NSRange(location: match.range.location, length: match.range.length - 1)
                if let swiftRange = Range(keyRange, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Boolean/null
        let literals = ["true", "false", "null"]
        for literal in literals {
            if let regex = try? NSRegularExpression(pattern: "\\b\(literal)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        return tokens
    }

    // MARK: - YAML Tokenization

    private func tokenizeYAML(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Keys (word followed by colon)
        if let regex = try? NSRegularExpression(pattern: "^\\s*([a-zA-Z_][a-zA-Z0-9_-]*)\\s*:", options: .anchorsMatchLines) {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if match.numberOfRanges > 1, let keyRange = Range(match.range(at: 1), in: code) {
                    tokens.append(Token(range: keyRange, type: .property))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b-?\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Booleans and null
        let literals = ["true", "false", "yes", "no", "on", "off", "null", "~"]
        for literal in literals {
            if let regex = try? NSRegularExpression(pattern: "\\b\(literal)\\b", options: .caseInsensitive) {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        return tokens
    }

    // MARK: - C/C++/ObjC Tokenization

    private func tokenizeCFamily(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "auto", "break", "case", "char", "const", "continue", "default", "do",
            "double", "else", "enum", "extern", "float", "for", "goto", "if",
            "inline", "int", "long", "register", "restrict", "return", "short",
            "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
            "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Imaginary",
            "class", "public", "private", "protected", "virtual", "override", "final",
            "new", "delete", "this", "template", "typename", "namespace", "using", "try",
            "catch", "throw", "throws", "import", "package", "interface", "implements",
            "nil", "NULL", "self", "super", "YES", "NO", "id", "SEL", "IMP", "Block"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Types
        if let regex = try? NSRegularExpression(pattern: "\\b(int|char|float|double|long|short|void|bool|size_t|NSTimeInterval|UIImage|CGPoint|CGRect|NSString)\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .type))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?[fFlL]?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Functions
        if let regex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if match.numberOfRanges > 1, let fnRange = Range(match.range(at: 1), in: code) {
                    tokens.append(Token(range: fnRange, type: .function))
                }
            }
        }

        return tokens
    }

    // MARK: - Java/Kotlin Tokenization

    private func tokenizeJava(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
            "class", "const", "continue", "default", "do", "double", "else", "enum",
            "extends", "final", "finally", "float", "for", "goto", "if", "implements",
            "import", "instanceof", "int", "interface", "long", "native", "new", "package",
            "private", "protected", "public", "return", "short", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws", "transient",
            "try", "void", "volatile", "while", "true", "false", "null",
            "fun", "val", "var", "object", "data", "sealed", "in", "out", "by", "is", "as"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?[fFdDlL]?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - Go Tokenization

    private func tokenizeGo(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
            "map", "package", "range", "return", "select", "struct", "switch", "type",
            "var", "true", "false", "iota", "nil", "append", "cap", "close", "complex",
            "copy", "delete", "imag", "len", "make", "new", "panic", "print", "println",
            "real", "recover"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - Rust Tokenization

    private func tokenizeRust(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
            "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
            "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
            "abstract", "become", "box", "do", "final", "macro", "override", "priv",
            "try", "typeof", "unsized", "virtual", "yield"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Lifetimes
        if let regex = try? NSRegularExpression(pattern: "'[a-zA-Z_][a-zA-Z0-9_]*") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?([fiu](8|16|32|64|size))?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - SQL Tokenization

    private func tokenizeSQL(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "INSERT", "INTO", "VALUES",
            "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "INDEX",
            "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "ORDER", "BY",
            "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "NULL",
            "IS", "LIKE", "IN", "BETWEEN", "CASE", "WHEN", "THEN", "ELSE", "END",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK",
            "UNIQUE", "EXISTS", "COUNT", "SUM", "AVG", "MIN", "MAX", "VARCHAR", "INT",
            "INTEGER", "TEXT", "REAL", "BLOB", "BOOLEAN", "DATE", "DATETIME", "TIMESTAMP"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b", options: .caseInsensitive) {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - HTML/XML Tokenization

    private func tokenizeHTML(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Tags
        if let regex = try? NSRegularExpression(pattern: "</?[a-zA-Z][a-zA-Z0-9-]*") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .keyword))
                }
            }
        }

        // Attributes
        if let regex = try? NSRegularExpression(pattern: "\\b[a-zA-Z-]+(?==)") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        return tokens
    }

    // MARK: - CSS Tokenization

    private func tokenizeCSS(_ code: String) -> [Token] {
        var tokens: [Token] = []

        let keywords = [
            "@import", "@media", "@keyframes", "@font-face", "@charset", "@supports",
            "important", "inherit", "initial", "unset", "none", "auto", "normal"
        ]

        for keyword in keywords {
            if let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b") {
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    if let swiftRange = Range(match.range, in: code) {
                        tokens.append(Token(range: swiftRange, type: .keyword))
                    }
                }
            }
        }

        // Properties
        if let regex = try? NSRegularExpression(pattern: "[a-zA-Z-]+(?=\\s*:)") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?(px|em|rem|%|vh|vw|pt|cm|mm|in)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        // Colors (hex)
        if let regex = try? NSRegularExpression(pattern: "#[0-9a-fA-F]{3,8}\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }

    // MARK: - Markdown Tokenization

    private func tokenizeMarkdown(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Headers
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s.*$", options: .anchorsMatchLines) {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .keyword))
                }
            }
        }

        // Bold/Italic
        if let regex = try? NSRegularExpression(pattern: "\\*\\*[^*]+\\*\\*|__[^_]+__|\\*[^*]+\\*|_[^_]+_") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .keyword))
                }
            }
        }

        // Code blocks
        if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```|`[^`]+`") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .string))
                }
            }
        }

        // Links
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .property))
                }
            }
        }

        return tokens
    }

    // MARK: - Generic Tokenization

    private func tokenizeGeneric(_ code: String) -> [Token] {
        var tokens: [Token] = []

        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code) {
                    tokens.append(Token(range: swiftRange, type: .number))
                }
            }
        }

        return tokens
    }
}

// MARK: - SwiftUI Integration

/// A SwiftUI Text view with syntax highlighting
public struct HighlightedText: View {
    let code: String
    let language: SyntaxHighlighter.Language
    let theme: SyntaxHighlighter.Theme

    public init(
        code: String,
        language: SyntaxHighlighter.Language = .swift,
        theme: SyntaxHighlighter.Theme = .xcodeLight
    ) {
        self.code = code
        self.language = language
        self.theme = theme
    }

    public var body: some View {
        Text(SyntaxHighlighter(theme: theme).highlight(code, language: language))
    }
}

// MARK: - NSViewRepresentable for NSTextView

#if os(macOS)
import AppKit

/// An NSTextView wrapper with syntax highlighting
public class SyntaxHighlightingTextView: NSTextView {
    private var highlighter: SyntaxHighlighter?
    private var language: SyntaxHighlighter.Language = .swift

    public func configure(highlighter: SyntaxHighlighter, language: SyntaxHighlighter.Language) {
        self.highlighter = highlighter
        self.language = language
    }

    public func setCode(_ code: String, language: SyntaxHighlighter.Language) {
        self.language = language
        let nsAttrString = highlighter?.highlightNS(code, language: language) ?? NSAttributedString(string: code)
        textStorage?.setAttributedString(nsAttrString)
    }

    public override func didChangeText() {
        super.didChangeText()
        guard let text = textStorage?.string, let highlighter = highlighter else { return }
        let nsAttrString = highlighter.highlightNS(text, language: language)
        textStorage?.setAttributedString(nsAttrString)
    }
}

/// NSViewRepresentable wrapper for SyntaxHighlightingTextView
public struct SyntaxHighlightingTextViewRepresentable: NSViewRepresentable {
    let code: String
    let language: SyntaxHighlighter.Language
    let theme: SyntaxHighlighter.Theme

    public init(
        code: String,
        language: SyntaxHighlighter.Language = .swift,
        theme: SyntaxHighlighter.Theme = .xcodeLight
    ) {
        self.code = code
        self.language = language
        self.theme = theme
    }

    public func makeNSView(context: Context) -> SyntaxHighlightingTextView {
        let textView = SyntaxHighlightingTextView()
        textView.configure(highlighter: SyntaxHighlighter(theme: theme), language: language)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        return textView
    }

    public func updateNSView(_ nsView: SyntaxHighlightingTextView, context: Context) {
        nsView.setCode(code, language: language)
    }
}
#endif

// MARK: - Language Detection

extension SyntaxHighlighter {

    /// Detect the programming language from a code string
    /// - Parameter code: The code to analyze
    /// - Returns: The detected language, or .plaintext if unknown
    public static func detectLanguage(from code: String) -> Language {
        // Swift
        if code.contains("func ") && code.contains("import Foundation") || code.contains("import SwiftUI") {
            return .swift
        }
        if code.contains("guard ") && code.contains("let ") && code.contains("->") {
            return .swift
        }

        // Python
        if code.contains("def ") && code.contains(":") && !code.contains("{") {
            return .python
        }
        if code.contains("import ") && code.contains("print(") {
            return .python
        }

        // JavaScript/TypeScript
        if code.contains("function ") || code.contains("=>") {
            if code.contains(": string") || code.contains(": number") || code.contains("interface ") {
                return .typescript
            }
            return .javascript
        }

        // Go
        if code.contains("func ") && code.contains("package ") && code.contains("fmt.") {
            return .go
        }

        // Rust
        if code.contains("fn ") && code.contains("let mut") || code.contains("impl ") {
            return .rust
        }

        // JSON
        if code.trimmingCharacters(in: .whitespaces).hasPrefix("{") &&
           code.trimmingCharacters(in: .whitespaces).hasSuffix("}") {
            return .json
        }

        // YAML
        if code.contains(": ") && !code.contains(";") && code.count(where: { $0 == ":" }) < 5 {
            return .yaml
        }

        // HTML/XML
        if code.contains("<!DOCTYPE") || code.contains("<html") || code.contains("<?xml") {
            return .html
        }
        if code.contains("<") && code.contains(">") && code.contains("/>") {
            return .xml
        }

        // Shell
        if code.hasPrefix("#!") || code.contains("echo ") || code.contains("export ") {
            return .shell
        }

        // SQL
        if code.contains("SELECT ") && code.contains("FROM ") {
            return .sql
        }

        return .plaintext
    }
}

// MARK: - Preview

#if DEBUG
struct SyntaxHighlighter_Previews: PreviewProvider {
    static let sampleCode = """
    func greet(name: String) -> String {
        let message = "Hello, \\(name)!"
        print(message)
        return message
    }
    """

    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Swift Code:").font(.headline)
            HighlightedText(code: sampleCode, language: .swift)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
