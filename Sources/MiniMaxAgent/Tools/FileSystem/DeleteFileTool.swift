import Foundation

/// Tool for deleting files and directories
public actor DeleteFileTool {
    
    /// Configuration for delete operations
    public struct Config: Sendable {
        /// Move to trash instead of permanent delete (safer)
        public let useTrash: Bool
        
        /// Require confirmation for directory deletion
        public let confirmDirectoryDeletion: Bool
        
        /// Delete empty parent directories after deletion
        public let cleanupEmptyParents: Bool
        
        /// Maximum number of items to delete in batch operations
        public let maxBatchSize: Int
        
        public init(
            useTrash: Bool = true,
            confirmDirectoryDeletion: Bool = true,
            cleanupEmptyParents: Bool = false,
            maxBatchSize: Int = 1000
        ) {
            self.useTrash = useTrash
            self.confirmDirectoryDeletion = confirmDirectoryDeletion
            self.cleanupEmptyParents = cleanupEmptyParents
            self.maxBatchSize = maxBatchSize
        }
    }
    
    /// Result of a delete operation
    public struct DeleteResult: Sendable, Equatable {
        /// Path that was deleted
        public let path: String
        
        /// Whether the delete was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// Whether the item was moved to trash
        public let movedToTrash: Bool
        
        /// Number of items deleted (for directories)
        public let itemsDeleted: Int
        
        /// Total bytes freed
        public let bytesFreed: Int64
        
        public init(
            path: String,
            success: Bool,
            error: String? = nil,
            movedToTrash: Bool = false,
            itemsDeleted: Int = 1,
            bytesFreed: Int64 = 0
        ) {
            self.path = path
            self.success = success
            self.error = error
            self.movedToTrash = movedToTrash
            self.itemsDeleted = itemsDeleted
            self.bytesFreed = bytesFreed
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Delete a file or directory at the given path
    public func delete(path: String, recursive: Bool = false) async -> DeleteResult {
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return DeleteResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        // Check if path exists
        guard fileManager.fileExists(atPath: path) else {
            return DeleteResult(
                path: path,
                success: false,
                error: "Path does not exist: \(path)"
            )
        }
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        
        if isDirectory.boolValue && !recursive {
            return DeleteResult(
                path: path,
                success: false,
                error: "Cannot delete directory without recursive=true: \(path)"
            )
        }
        
        // Calculate size before deletion
        let sizeToFree = calculateSize(at: path)
        
        do {
            if config.useTrash {
                // Move to trash using FileManager
                let trashPath = NSHomeDirectory() + "/.Trash/" + (path as NSString).lastPathComponent
                try FileManager.default.moveItem(atPath: path, toPath: trashPath)
                
                return DeleteResult(
                    path: path,
                    success: true,
                    movedToTrash: true,
                    itemsDeleted: 1,
                    bytesFreed: sizeToFree
                )
            } else {
                // Permanent deletion
                if isDirectory.boolValue {
                    try fileManager.removeItem(atPath: path)
                } else {
                    try fileManager.removeItem(atPath: path)
                }
                
                // Cleanup empty parent directories if requested
                if config.cleanupEmptyParents {
                    cleanupEmptyParents(path: URL(fileURLWithPath: path).deletingLastPathComponent().path)
                }
                
                return DeleteResult(
                    path: path,
                    success: true,
                    movedToTrash: false,
                    itemsDeleted: 1,
                    bytesFreed: sizeToFree
                )
            }
        } catch {
            return DeleteResult(
                path: path,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Delete multiple items
    public func deleteBatch(paths: [String], recursive: Bool = false) async -> [DeleteResult] {
        guard paths.count <= config.maxBatchSize else {
            return paths.map { path in
                DeleteResult(
                    path: path,
                    success: false,
                    error: "Batch size exceeds maximum of \(config.maxBatchSize)"
                )
            }
        }
        
        return await withTaskGroup(of: DeleteResult.self) { group in
            for path in paths {
                group.addTask {
                    await self.delete(path: path, recursive: recursive)
                }
            }
            
            var results: [DeleteResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    /// Calculate total size of a path
    private func calculateSize(at path: String) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return 0
        }
        
        if isDirectory.boolValue {
            return calculateDirectorySize(at: path)
        } else {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                return attributes[.size] as? Int64 ?? 0
            } catch {
                return 0
            }
        }
    }
    
    /// Calculate total size of a directory
    private func calculateDirectorySize(at path: String) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fullPath)
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    /// Remove empty parent directories
    private func cleanupEmptyParents(path: String) {
        let fileManager = FileManager.default
        
        var currentPath = path
        while currentPath != "/" && currentPath != "" {
            if fileManager.fileExists(atPath: currentPath) {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: currentPath, isDirectory: &isDirectory)
                
                if !isDirectory.boolValue {
                    break
                }
                
                // Check if directory is empty
                if let contents = try? fileManager.contentsOfDirectory(atPath: currentPath),
                   contents.isEmpty {
                    try? fileManager.removeItem(atPath: currentPath)
                } else {
                    break
                }
            }
            
            let url = URL(fileURLWithPath: currentPath)
            currentPath = url.deletingLastPathComponent().path
        }
    }
    
    /// Check if path is safe (no path traversal)
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
}

/// Options for delete_file tool
public struct DeleteFileOptions: Sendable {
    /// Move to trash instead of permanent delete
    public let useTrash: Bool
    
    /// Delete directories recursively
    public let recursive: Bool
    
    /// Clean up empty parent directories
    public let cleanupParents: Bool
    
    public init(
        useTrash: Bool = true,
        recursive: Bool = false,
        cleanupParents: Bool = false
    ) {
        self.useTrash = useTrash
        self.recursive = recursive
        self.cleanupParents = cleanupParents
    }
}
