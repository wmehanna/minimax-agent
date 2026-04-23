import Foundation

/// Tool for reading file contents with various options
public actor ReadFileTool {
    
    /// Configuration for read operations
    public struct Config: Sendable {
        /// Maximum file size to read in bytes (default: 10MB)
        public let maxFileSize: Int64
        
        /// Encoding to use if not auto-detected
        public let encoding: String.Encoding?
        
        /// Whether to include line numbers in output
        public let includeLineNumbers: Bool
        
        /// Maximum lines to read (0 = unlimited)
        public let maxLines: Int
        
        /// Starting line number (1-indexed, 0 = start from beginning)
        public let startLine: Int
        
        public init(
            maxFileSize: Int64 = 10_000_000,
            encoding: String.Encoding? = nil,
            includeLineNumbers: Bool = false,
            maxLines: Int = 0,
            startLine: Int = 0
        ) {
            self.maxFileSize = maxFileSize
            self.encoding = encoding
            self.includeLineNumbers = includeLineNumbers
            self.maxLines = maxLines
            self.startLine = startLine
        }
    }
    
    /// Result of a read operation
    public struct ReadResult: Sendable, Equatable {
        /// Path that was read
        public let path: String
        
        /// File contents (may be truncated)
        public let content: String
        
        /// Whether the read was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// File size in bytes
        public let fileSize: Int64
        
        /// Whether content was truncated
        public let truncated: Bool
        
        /// Number of lines read
        public let lineCount: Int
        
        /// File encoding used
        public let encoding: String
        
        /// Last modified date
        public let modifiedAt: Date
        
        public init(
            path: String,
            content: String,
            success: Bool,
            error: String? = nil,
            fileSize: Int64 = 0,
            truncated: Bool = false,
            lineCount: Int = 0,
            encoding: String = "utf-8",
            modifiedAt: Date = Date()
        ) {
            self.path = path
            self.content = content
            self.success = success
            self.error = error
            self.fileSize = fileSize
            self.truncated = truncated
            self.lineCount = lineCount
            self.encoding = encoding
            self.modifiedAt = modifiedAt
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Read a file at the given path
    public func read(path: String) async -> ReadResult {
        let url = URL(fileURLWithPath: path)
        
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return ReadResult(
                path: path,
                content: "",
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            return ReadResult(
                path: path,
                content: "",
                success: false,
                error: "File not found: \(path)"
            )
        }
        
        // Get file attributes
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            guard let fileSize = attributes[.size] as? Int64 else {
                return ReadResult(
                    path: path,
                    content: "",
                    success: false,
                    error: "Could not determine file size"
                )
            }
            
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            
            // Check file size limit
            if fileSize > config.maxFileSize {
                return ReadResult(
                    path: path,
                    content: "",
                    success: false,
                    error: "File too large: \(fileSize) bytes (max: \(config.maxFileSize))",
                    fileSize: fileSize
                )
            }
            
            // Read file contents
            let data = try Data(contentsOf: url)
            
            // Detect or use specified encoding
            let usedEncoding: String.Encoding
            var contentString: String
            
            if let encoding = config.encoding {
                // Use specified encoding
                usedEncoding = encoding
                guard let str = String(data: data, encoding: encoding) else {
                    return ReadResult(
                        path: path,
                        content: "",
                        success: false,
                        error: "Could not decode file with specified encoding",
                        fileSize: fileSize
                    )
                }
                contentString = str
            } else {
                // Try to detect encoding - try UTF-8 first
                if let str = String(data: data, encoding: .utf8) {
                    usedEncoding = .utf8
                    contentString = str
                } else if let str = String(data: data, encoding: .isoLatin1) {
                    // Try ISO Latin-1 as fallback
                    usedEncoding = .isoLatin1
                    contentString = str
                } else {
                    return ReadResult(
                        path: path,
                        content: "",
                        success: false,
                        error: "Could not detect file encoding",
                        fileSize: fileSize
                    )
                }
            }
            
            var truncated = false
            var lineCount = 0
            
            // Handle line limiting
            if config.maxLines > 0 || config.startLine > 0 {
                var lines = contentString.components(separatedBy: .newlines)
                let startIdx = max(0, config.startLine > 0 ? config.startLine - 1 : 0)
                let endIdx = config.maxLines > 0 ? min(startIdx + config.maxLines, lines.count) : lines.count
                
                if endIdx < lines.count {
                    truncated = true
                }
                
                lines = Array(lines[startIdx..<endIdx])
                lineCount = lines.count
                
                if config.includeLineNumbers {
                    contentString = lines.enumerated()
                        .map { idx, line in "\(startIdx + idx + 1): \(line)" }
                        .joined(separator: "\n")
                } else {
                    contentString = lines.joined(separator: "\n")
                }
            } else {
                lineCount = contentString.components(separatedBy: .newlines).count
                
                if config.includeLineNumbers {
                    contentString = contentString.components(separatedBy: .newlines)
                        .enumerated()
                        .map { idx, line in "\(idx + 1): \(line)" }
                        .joined(separator: "\n")
                }
            }
            
            return ReadResult(
                path: path,
                content: contentString,
                success: true,
                fileSize: fileSize,
                truncated: truncated,
                lineCount: lineCount,
                encoding: String(describing: usedEncoding),
                modifiedAt: modifiedAt
            )
            
        } catch {
            return ReadResult(
                path: path,
                content: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Check if path is safe (no path traversal)
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
}

/// Options for read_file tool
public struct ReadFileOptions: Sendable {
    /// Maximum file size in bytes (default: 10MB)
    public let maxFileSize: Int64
    
    /// Starting line number (1-indexed, 0 = from beginning)
    public let startLine: Int
    
    /// Maximum lines to read (0 = all)
    public let maxLines: Int
    
    /// Include line numbers in output
    public let lineNumbers: Bool
    
    /// File encoding (nil for auto-detect)
    public let encoding: String?
    
    public init(
        maxFileSize: Int64 = 10_000_000,
        startLine: Int = 0,
        maxLines: Int = 0,
        lineNumbers: Bool = false,
        encoding: String? = nil
    ) {
        self.maxFileSize = maxFileSize
        self.startLine = startLine
        self.maxLines = maxLines
        self.lineNumbers = lineNumbers
        self.encoding = encoding
    }
}
