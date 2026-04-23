import Foundation

/// Unified file system operations tool for the agentic coding engine
/// Provides read, write, delete, list, and create operations with consistent interface
public actor FileSystemTools {
    
    /// Unified result type for all file system operations
    public enum OperationResult: Sendable, Equatable {
        case read(ReadFileTool.ReadResult)
        case write(WriteFileTool.WriteResult)
        case delete(DeleteFileTool.DeleteResult)
        case list(ListDirectoryTool.ListResult)
        case createDirectory(CreateDirectoryTool.CreateResult)
        
        /// Whether the operation succeeded
        public var success: Bool {
            switch self {
            case .read(let r): return r.success
            case .write(let r): return r.success
            case .delete(let r): return r.success
            case .list(let r): return r.success
            case .createDirectory(let r): return r.success
            }
        }
        
        /// Error message if failed
        public var error: String? {
            switch self {
            case .read(let r): return r.error
            case .write(let r): return r.error
            case .delete(let r): return r.error
            case .list(let r): return r.error
            case .createDirectory(let r): return r.error
            }
        }
        
        /// Path involved in the operation
        public var path: String {
            switch self {
            case .read(let r): return r.path
            case .write(let r): return r.path
            case .delete(let r): return r.path
            case .list(let r): return r.path
            case .createDirectory(let r): return r.path
            }
        }
    }
    
    /// Tool configuration
    public struct ToolsConfig: Sendable {
        public let readConfig: ReadFileTool.Config
        public let writeConfig: WriteFileTool.Config
        public let deleteConfig: DeleteFileTool.Config
        public let listConfig: ListDirectoryTool.Config
        public let createConfig: CreateDirectoryTool.Config
        
        /// Default configuration with reasonable safety limits
        public static let `default` = ToolsConfig(
            readConfig: ReadFileTool.Config(maxFileSize: 10_000_000),
            writeConfig: WriteFileTool.Config(),
            deleteConfig: DeleteFileTool.Config(useTrash: true),
            listConfig: ListDirectoryTool.Config(),
            createConfig: CreateDirectoryTool.Config()
        )
        
        public init(
            readConfig: ReadFileTool.Config = ReadFileTool.Config(),
            writeConfig: WriteFileTool.Config = WriteFileTool.Config(),
            deleteConfig: DeleteFileTool.Config = DeleteFileTool.Config(),
            listConfig: ListDirectoryTool.Config = ListDirectoryTool.Config(),
            createConfig: CreateDirectoryTool.Config = CreateDirectoryTool.Config()
        ) {
            self.readConfig = readConfig
            self.writeConfig = writeConfig
            self.deleteConfig = deleteConfig
            self.listConfig = listConfig
            self.createConfig = createConfig
        }
    }
    
    private let readTool: ReadFileTool
    private let writeTool: WriteFileTool
    private let deleteTool: DeleteFileTool
    private let listTool: ListDirectoryTool
    private let createTool: CreateDirectoryTool
    
    public init(config: ToolsConfig = .default) {
        self.readTool = ReadFileTool(config: config.readConfig)
        self.writeTool = WriteFileTool(config: config.writeConfig)
        self.deleteTool = DeleteFileTool(config: config.deleteConfig)
        self.listTool = ListDirectoryTool(config: config.listConfig)
        self.createTool = CreateDirectoryTool(config: config.createConfig)
    }
    
    // MARK: - Unified Operations
    
    /// Read a file
    public func read(path: String, options: ReadFileOptions? = nil) async -> OperationResult {
        let result = await readTool.read(path: path)
        return .read(result)
    }
    
    /// Write content to a file
    public func write(path: String, content: String, options: WriteFileOptions? = nil) async -> OperationResult {
        let result = await writeTool.write(path: path, content: content)
        return .write(result)
    }
    
    /// Delete a file or directory
    public func delete(path: String, options: DeleteFileOptions? = nil) async -> OperationResult {
        let recursive = options?.recursive ?? false
        let result = await deleteTool.delete(path: path, recursive: recursive)
        return .delete(result)
    }
    
    /// List directory contents
    public func list(path: String, options: ListDirectoryOptions? = nil) async -> OperationResult {
        let result = await listTool.list(path: path)
        return .list(result)
    }
    
    /// Create a directory
    public func createDirectory(path: String, options: CreateDirectoryOptions? = nil) async -> OperationResult {
        let result = await createTool.create(path: path)
        return .createDirectory(result)
    }
    
    /// Move/rename a file or directory
    public func move(from source: String, to destination: String) async -> OperationResult {
        // Security checks
        guard isPathSafe(source) && isPathSafe(destination) else {
            return .delete(DeleteFileTool.DeleteResult(
                path: source,
                success: false,
                error: "Path traversal detected"
            ))
        }
        
        let fileManager = FileManager.default
        
        do {
            try fileManager.moveItem(atPath: source, toPath: destination)
            return .delete(DeleteFileTool.DeleteResult(
                path: source,
                success: true
            ))
        } catch {
            return .delete(DeleteFileTool.DeleteResult(
                path: source,
                success: false,
                error: error.localizedDescription
            ))
        }
    }
    
    /// Copy a file or directory
    public func copy(from source: String, to destination: String) async -> OperationResult {
        guard isPathSafe(source) && isPathSafe(destination) else {
            return .delete(DeleteFileTool.DeleteResult(
                path: source,
                success: false,
                error: "Path traversal detected"
            ))
        }
        
        let fileManager = FileManager.default
        
        do {
            try fileManager.copyItem(atPath: source, toPath: destination)
            return .write(WriteFileTool.WriteResult(
                path: destination,
                success: true,
                created: true
            ))
        } catch {
            return .write(WriteFileTool.WriteResult(
                path: destination,
                success: false,
                error: error.localizedDescription
            ))
        }
    }
    
    /// Check if a path exists
    public func exists(_ path: String) async -> Bool {
        guard isPathSafe(path) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// Get file/directory information
    public func info(_ path: String) async -> DetailedFileInfo? {
        guard isPathSafe(path) else { return nil }
        
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else { return nil }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            
            let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
            let size = (attributes[.size] as? Int64) ?? 0
            let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date()
            let createdAt = (attributes[.creationDate] as? Date) ?? Date()
            let permissions = (attributes[.posixPermissions] as? Int) ?? 0
            
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let parentPath = url.deletingLastPathComponent().path
            let ext = isDirectory ? nil : url.pathExtension.isEmpty ? nil : url.pathExtension
            
            let isReadable = fileManager.isReadableFile(atPath: path)
            let isWritable = fileManager.isWritableFile(atPath: path)
            
            return DetailedFileInfo(
                path: path,
                name: name,
                parentPath: parentPath,
                extension_: ext,
                size: size,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                isDirectory: isDirectory,
                isSymbolicLink: false,
                permissions: formatPermissions(permissions),
                lineCount: nil,
                encoding: nil,
                isReadable: isReadable,
                isWritable: isWritable
            )
        } catch {
            return nil
        }
    }
    
    /// Path security check
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
    
    private func formatPermissions(_ permissions: Int) -> String {
        let u = (permissions / 100) % 10
        let g = (permissions / 10) % 10
        let o = permissions % 10
        return "\(u)\(g)\(o)"
    }
}

// MARK: - Tool Definitions for LLM

/// Tool definitions for LLM function calling (schema format)
public struct FileSystemToolDefinitions {
    
    public static let readFile = ToolDefinition(
        name: "read_file",
        description: "Read the contents of a file from the file system",
        inputSchema: .object([
            "path": .string(description: "Path to the file to read"),
            "options": .optional(.object([
                "maxFileSize": .integer(description: "Maximum file size in bytes", default: 10_000_000),
                "startLine": .integer(description: "Starting line number (1-indexed)", default: 0),
                "maxLines": .integer(description: "Maximum lines to read", default: 0),
                "lineNumbers": .boolean(description: "Include line numbers in output", default: false),
                "encoding": .optional(.string(description: "File encoding (e.g., utf-8, isoLatin1)"))
            ]))
        ])
    )
    
    public static let writeFile = ToolDefinition(
        name: "write_file",
        description: "Write content to a file, creating it if it doesn't exist",
        inputSchema: .object([
            "path": .string(description: "Path to the file to write"),
            "content": .string(description: "Content to write to the file"),
            "options": .optional(.object([
                "createParents": .boolean(description: "Create parent directories if needed", default: true),
                "backup": .boolean(description: "Backup existing file before writing", default: true),
                "force": .boolean(description: "Overwrite without backup", default: false)
            ]))
        ])
    )
    
    public static let deleteFile = ToolDefinition(
        name: "delete_file",
        description: "Delete a file or directory",
        inputSchema: .object([
            "path": .string(description: "Path to the file or directory to delete"),
            "options": .optional(.object([
                "useTrash": .boolean(description: "Move to trash instead of permanent delete", default: true),
                "recursive": .boolean(description: "Delete directories recursively", default: false)
            ]))
        ])
    )
    
    public static let listDirectory = ToolDefinition(
        name: "list_directory",
        description: "List contents of a directory",
        inputSchema: .object([
            "path": .string(description: "Path to the directory to list"),
            "options": .optional(.object([
                "includeHidden": .boolean(description: "Include hidden files", default: false),
                "sortBy": .string(description: "Sort by: name, date_modified, size, type", default: "name"),
                "order": .string(description: "Sort order: asc, desc", default: "asc"),
                "maxItems": .integer(description: "Maximum items to return", default: 0),
                "includeStats": .boolean(description: "Include file statistics", default: false)
            ]))
        ])
    )
    
    public static let createDirectory = ToolDefinition(
        name: "create_directory",
        description: "Create a new directory",
        inputSchema: .object([
            "path": .string(description: "Path to the directory to create"),
            "options": .optional(.object([
                "createParents": .boolean(description: "Create intermediate parent directories", default: true),
                "ignoreExisting": .boolean(description: "Don't error if directory exists", default: true),
                "permissions": .optional(.string(description: "Permissions (e.g., 755)"))
            ]))
        ])
    )
}

/// Minimal tool definition structure
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema
    
    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// JSON Schema types for tool definitions
public indirect enum JSONSchema: Sendable {
    case string(description: String, default: String? = nil)
    case integer(description: String, default: Int = 0)
    case boolean(description: String, default: Bool = false)
    case object([String: JSONSchema])
    case optional(JSONSchema)
    
    public var type: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .object: return "object"
        case .optional: return "string"
        }
    }
}
