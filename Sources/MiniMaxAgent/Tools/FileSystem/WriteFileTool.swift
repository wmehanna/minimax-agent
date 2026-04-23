import Foundation

/// Tool for writing content to files
public actor WriteFileTool {
    
    /// Configuration for write operations
    public struct Config: Sendable {
        /// Default encoding to use
        public let encoding: String.Encoding
        
        /// Create parent directories if they don't exist
        public let createParentDirectories: Bool
        
        /// Backup existing files before writing
        public let backupExisting: Bool
        
        /// Backup suffix (e.g., ".bak")
        public let backupSuffix: String
        
        public init(
            encoding: String.Encoding = .utf8,
            createParentDirectories: Bool = true,
            backupExisting: Bool = true,
            backupSuffix: String = ".bak"
        ) {
            self.encoding = encoding
            self.createParentDirectories = createParentDirectories
            self.backupExisting = backupExisting
            self.backupSuffix = backupSuffix
        }
    }
    
    /// Result of a write operation
    public struct WriteResult: Sendable, Equatable {
        /// Path that was written
        public let path: String
        
        /// Whether the write was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// Number of bytes written
        public let bytesWritten: Int64
        
        /// Number of lines written
        public let lineCount: Int
        
        /// Whether a backup was created
        public let backupCreated: Bool
        
        /// Path to backup file if created
        public let backupPath: String?
        
        /// Whether file was created (vs updated)
        public let created: Bool
        
        public init(
            path: String,
            success: Bool,
            error: String? = nil,
            bytesWritten: Int64 = 0,
            lineCount: Int = 0,
            backupCreated: Bool = false,
            backupPath: String? = nil,
            created: Bool = false
        ) {
            self.path = path
            self.success = success
            self.error = error
            self.bytesWritten = bytesWritten
            self.lineCount = lineCount
            self.backupCreated = backupCreated
            self.backupPath = backupPath
            self.created = created
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Write content to a file at the given path
    public func write(path: String, content: String, force: Bool = false) async -> WriteResult {
        let url = URL(fileURLWithPath: path)
        
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return WriteResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        // Check if file exists
        let fileExists = fileManager.fileExists(atPath: path)
        
        // Handle existing file
        var backupPath: String?
        var backupCreated = false
        
        if fileExists {
            // Check if we should backup
            if config.backupExisting && !force {
                let backupURL = url.appendingPathExtension(config.backupSuffix.replacingOccurrences(of: ".", with: ""))
                do {
                    // Remove old backup if exists
                    if fileManager.fileExists(atPath: backupURL.path) {
                        try fileManager.removeItem(at: backupURL)
                    }
                    try fileManager.copyItem(at: url, to: backupURL)
                    backupPath = backupURL.path
                    backupCreated = true
                } catch {
                    return WriteResult(
                        path: path,
                        success: false,
                        error: "Failed to create backup: \(error.localizedDescription)"
                    )
                }
            }
            
            // Check if file is writable
            guard fileManager.isWritableFile(atPath: path) else {
                return WriteResult(
                    path: path,
                    success: false,
                    error: "File is not writable: \(path)"
                )
            }
        } else {
            // File doesn't exist - check parent directory
            let parentURL = url.deletingLastPathComponent()
            
            if !fileManager.fileExists(atPath: parentURL.path) {
                if config.createParentDirectories {
                    do {
                        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
                    } catch {
                        return WriteResult(
                            path: path,
                            success: false,
                            error: "Failed to create parent directory: \(error.localizedDescription)"
                        )
                    }
                } else {
                    return WriteResult(
                        path: path,
                        success: false,
                        error: "Parent directory does not exist: \(parentURL.path)"
                    )
                }
            }
        }
        
        // Write the file
        do {
            guard let data = content.data(using: config.encoding) else {
                return WriteResult(
                    path: path,
                    success: false,
                    error: "Failed to encode content with encoding: \(config.encoding)"
                )
            }
            
            try data.write(to: url, options: force ? .atomic : .atomic)
            
            let lineCount = content.components(separatedBy: .newlines).count
            
            return WriteResult(
                path: path,
                success: true,
                bytesWritten: Int64(data.count),
                lineCount: lineCount,
                backupCreated: backupCreated,
                backupPath: backupPath,
                created: !fileExists
            )
            
        } catch {
            return WriteResult(
                path: path,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Append content to a file
    public func append(path: String, content: String) async -> WriteResult {
        let url = URL(fileURLWithPath: path)
        
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return WriteResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        // Check if file exists
        if !fileManager.fileExists(atPath: path) {
            // If file doesn't exist, just write it
            return await write(path: path, content: content)
        }
        
        // Append to existing file
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            
            try handle.seekToEnd()
            
            guard let data = content.data(using: config.encoding) else {
                return WriteResult(
                    path: path,
                    success: false,
                    error: "Failed to encode content"
                )
            }
            
            try handle.write(contentsOf: data)
            
            let lineCount = content.components(separatedBy: .newlines).count
            
            return WriteResult(
                path: path,
                success: true,
                bytesWritten: Int64(data.count),
                lineCount: lineCount,
                created: false
            )
            
        } catch {
            return WriteResult(
                path: path,
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

/// Options for write_file tool
public struct WriteFileOptions: Sendable {
    /// Create parent directories if needed
    public let createParents: Bool
    
    /// Backup existing file before writing
    public let backup: Bool
    
    /// Force write (overwrite without backup)
    public let force: Bool
    
    /// Backup file suffix
    public let backupSuffix: String
    
    public init(
        createParents: Bool = true,
        backup: Bool = true,
        force: Bool = false,
        backupSuffix: String = "bak"
    ) {
        self.createParents = createParents
        self.backup = backup
        self.force = force
        self.backupSuffix = backupSuffix
    }
}
