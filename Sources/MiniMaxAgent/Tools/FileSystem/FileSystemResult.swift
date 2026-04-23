import Foundation

/// Represents the result of a file system operation
public struct FileSystemResult: Sendable, Equatable {
    /// Path involved in the operation
    public let path: String
    
    /// Whether the operation succeeded
    public let success: Bool
    
    /// Error message if the operation failed
    public let error: String?
    
    /// Human-readable description
    public var description: String {
        if success {
            return "Success: \(path)"
        } else {
            return "Error: \(error ?? "Unknown error") at \(path)"
        }
    }
    
    public init(path: String, success: Bool, error: String? = nil) {
        self.path = path
        self.success = success
        self.error = error
    }
}

/// Represents detailed file information
public struct DetailedFileInfo: Sendable, Equatable, Codable {
    /// Full path to the file
    public let path: String
    
    /// File name (last path component)
    public let name: String
    
    /// Parent directory path
    public let parentPath: String
    
    /// File extension (without leading dot)
    public let extension_: String?
    
    /// File size in bytes
    public let size: Int64
    
    /// Last modification date
    public let modifiedAt: Date
    
    /// Creation date
    public let createdAt: Date
    
    /// Whether it's a directory
    public let isDirectory: Bool
    
    /// Whether it's a symbolic link
    public let isSymbolicLink: Bool
    
    /// Permissions string (e.g., "rw-r--r--")
    public let permissions: String
    
    /// Number of lines (for text files)
    public let lineCount: Int?
    
    /// File encoding (for text files)
    public let encoding: String?
    
    /// Whether the file is readable
    public let isReadable: Bool
    
    /// Whether the file is writable
    public let isWritable: Bool
    
    enum CodingKeys: String, CodingKey {
        case path, name, parentPath, extension_ = "extension", size
        case modifiedAt, createdAt, isDirectory, isSymbolicLink
        case permissions, lineCount, encoding, isReadable, isWritable
    }
    
    public init(
        path: String,
        name: String,
        parentPath: String,
        extension_: String?,
        size: Int64,
        modifiedAt: Date,
        createdAt: Date,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        permissions: String,
        lineCount: Int?,
        encoding: String?,
        isReadable: Bool,
        isWritable: Bool
    ) {
        self.path = path
        self.name = name
        self.parentPath = parentPath
        self.extension_ = extension_
        self.size = size
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.permissions = permissions
        self.lineCount = lineCount
        self.encoding = encoding
        self.isReadable = isReadable
        self.isWritable = isWritable
    }
}
