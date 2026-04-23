import Foundation

/// Tool for creating directories
public actor CreateDirectoryTool {
    
    /// Configuration for create operations
    public struct Config: Sendable {
        /// Create intermediate parent directories
        public let createIntermediateDirectories: Bool
        
        /// Set specific permissions (via chmod)
        public let permissions: Int?
        
        /// Don't error if directory exists
        public let ignoreExisting: Bool
        
        public init(
            createIntermediateDirectories: Bool = true,
            permissions: Int? = nil,
            ignoreExisting: Bool = true
        ) {
            self.createIntermediateDirectories = createIntermediateDirectories
            self.permissions = permissions
            self.ignoreExisting = ignoreExisting
        }
    }
    
    /// Result of a create operation
    public struct CreateResult: Sendable, Equatable {
        /// Path that was created
        public let path: String
        
        /// Whether the create was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// Whether the directory was newly created
        public let created: Bool
        
        /// Permissions set on the directory
        public let permissions: String?
        
        public init(
            path: String,
            success: Bool,
            error: String? = nil,
            created: Bool = true,
            permissions: String? = nil
        ) {
            self.path = path
            self.success = success
            self.error = error
            self.created = created
            self.permissions = permissions
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Create a directory at the given path
    public func create(path: String) async -> CreateResult {
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return CreateResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        // Check if directory already exists
        if fileManager.fileExists(atPath: path) {
            if config.ignoreExisting {
                // Return success but indicate not created
                return CreateResult(
                    path: path,
                    success: true,
                    error: "Directory already exists",
                    created: false
                )
            } else {
                return CreateResult(
                    path: path,
                    success: false,
                    error: "Directory already exists: \(path)",
                    created: false
                )
            }
        }
        
        do {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: config.createIntermediateDirectories,
                attributes: config.permissions.map { [.posixPermissions: $0] }
            )
            
            // Set permissions if specified
            var finalPermissions: String?
            if let perms = config.permissions {
                finalPermissions = formatPermissions(perms)
            } else {
                // Get the actual permissions that were set
                if let attrs = try? fileManager.attributesOfItem(atPath: path),
                   let posixPerms = attrs[.posixPermissions] as? Int {
                    finalPermissions = formatPermissions(posixPerms)
                }
            }
            
            return CreateResult(
                path: path,
                success: true,
                created: true,
                permissions: finalPermissions
            )
            
        } catch {
            return CreateResult(
                path: path,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Create multiple directories
    public func createBatch(paths: [String]) async -> [CreateResult] {
        return await withTaskGroup(of: CreateResult.self) { group in
            for path in paths {
                group.addTask {
                    await self.create(path: path)
                }
            }
            
            var results: [CreateResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    /// Create a temporary directory
    public func createTemporary(prefix: String = "minimax_agent_") async -> CreateResult {
        let tempDir = NSTemporaryDirectory()
        let uniqueName = prefix + UUID().uuidString
        let path = (tempDir as NSString).appendingPathComponent(uniqueName)
        
        return await create(path: path)
    }
    
    /// Check if path is safe (no path traversal)
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
    
    /// Format permissions integer to string (e.g., "755")
    private func formatPermissions(_ permissions: Int) -> String {
        let u = (permissions / 100) % 10
        let g = (permissions / 10) % 10
        let o = permissions % 10
        return "\(u)\(g)\(o)"
    }
}

/// Options for create_directory tool
public struct CreateDirectoryOptions: Sendable {
    /// Create intermediate parent directories
    public let createParents: Bool
    
    /// Don't error if directory exists
    public let ignoreExisting: Bool
    
    /// Permissions to set (octal string like "755" or integer)
    public let permissions: String?
    
    public init(
        createParents: Bool = true,
        ignoreExisting: Bool = true,
        permissions: String? = nil
    ) {
        self.createParents = createParents
        self.ignoreExisting = ignoreExisting
        self.permissions = permissions
    }
}
