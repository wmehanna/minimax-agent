import Foundation

/// Tool for listing directory contents
public actor ListDirectoryTool {
    
    /// Configuration for list operations
    public struct Config: Sendable {
        /// Include hidden files (starting with .)
        public let includeHidden: Bool
        
        /// Sort by which attribute
        public enum SortBy: Sendable {
            case name
            case dateModified
            case dateCreated
            case size
            case type
        }
        
        public let sortBy: SortBy
        
        /// Sort order
        public enum SortOrder: Sendable {
            case ascending
            case descending
        }
        
        public let sortOrder: SortOrder
        
        /// Maximum items to return (0 = unlimited)
        public let maxItems: Int
        
        /// Include file statistics (size, dates, permissions)
        public let includeStats: Bool
        
        /// Show full path instead of relative names
        public let fullPath: Bool
        
        public init(
            includeHidden: Bool = false,
            sortBy: SortBy = .name,
            sortOrder: SortOrder = .ascending,
            maxItems: Int = 0,
            includeStats: Bool = false,
            fullPath: Bool = false
        ) {
            self.includeHidden = includeHidden
            self.sortBy = sortBy
            self.sortOrder = sortOrder
            self.maxItems = maxItems
            self.includeStats = includeStats
            self.fullPath = fullPath
        }
    }
    
    /// Result of a list operation
    public struct ListResult: Sendable, Equatable {
        /// Path that was listed
        public let path: String
        
        /// Whether the list was successful
        public let success: Bool
        
        /// Error message if failed
        public let error: String?
        
        /// Items in the directory
        public let items: [ListedItem]
        
        /// Total count of items
        public let totalCount: Int
        
        /// Total size of all items (if includeStats was true)
        public let totalSize: Int64
        
        /// Whether the list was truncated
        public let truncated: Bool
        
        public init(
            path: String,
            success: Bool,
            error: String? = nil,
            items: [ListedItem] = [],
            totalCount: Int = 0,
            totalSize: Int64 = 0,
            truncated: Bool = false
        ) {
            self.path = path
            self.success = success
            self.error = error
            self.items = items
            self.totalCount = totalCount
            self.totalSize = totalSize
            self.truncated = truncated
        }
    }
    
    /// An item in a directory listing
    public struct ListedItem: Sendable, Equatable, Codable {
        /// Name of the item
        public let name: String
        
        /// Full path to the item
        public let path: String
        
        /// Whether it's a directory
        public let isDirectory: Bool
        
        /// File size in bytes (0 for directories)
        public let size: Int64
        
        /// Last modification date
        public let modifiedAt: Date
        
        /// Creation date
        public let createdAt: Date
        
        /// Permissions string
        public let permissions: String
        
        /// File extension
        public let extension_: String?
        
        enum CodingKeys: String, CodingKey {
            case name, path, isDirectory, size, modifiedAt, createdAt, permissions
            case extension_ = "extension"
        }
        
        public init(
            name: String,
            path: String,
            isDirectory: Bool,
            size: Int64 = 0,
            modifiedAt: Date = Date(),
            createdAt: Date = Date(),
            permissions: String = "",
            extension_: String? = nil
        ) {
            self.name = name
            self.path = path
            self.isDirectory = isDirectory
            self.size = size
            self.modifiedAt = modifiedAt
            self.createdAt = createdAt
            self.permissions = permissions
            self.extension_ = extension_
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// List contents of a directory
    public func list(path: String) async -> ListResult {
        // Security: prevent path traversal
        guard isPathSafe(path) else {
            return ListResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        // Check if path exists
        guard fileManager.fileExists(atPath: path) else {
            return ListResult(
                path: path,
                success: false,
                error: "Path does not exist: \(path)"
            )
        }
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ListResult(
                path: path,
                success: false,
                error: "Path is not a directory: \(path)"
            )
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            
            // Filter hidden files if needed
            var filteredContents = contents
            if !config.includeHidden {
                filteredContents = contents.filter { !$0.hasPrefix(".") }
            }
            
            // Get item details if needed
            var items: [ListedItem] = []
            var totalSize: Int64 = 0
            
            for name in filteredContents {
                let itemPath = (path as NSString).appendingPathComponent(name)
                
                if config.includeStats {
                    let item = try createListedItem(name: name, path: itemPath, basePath: path)
                    items.append(item)
                    totalSize += item.size
                } else {
                    let isDir = (try? fileManager.attributesOfItem(atPath: itemPath)[.type] as? FileAttributeType) == .typeDirectory
                    let ext = (name as NSString).pathExtension.isEmpty ? nil : (name as NSString).pathExtension
                    
                    items.append(ListedItem(
                        name: name,
                        path: config.fullPath ? itemPath : name,
                        isDirectory: isDir,
                        extension_: ext
                    ))
                }
            }
            
            // Sort items
            items = sortItems(items)
            
            // Truncate if needed
            var truncated = false
            if config.maxItems > 0 && items.count > config.maxItems {
                items = Array(items.prefix(config.maxItems))
                truncated = true
            }
            
            return ListResult(
                path: path,
                success: true,
                items: items,
                totalCount: filteredContents.count,
                totalSize: totalSize,
                truncated: truncated
            )
            
        } catch {
            return ListResult(
                path: path,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// List directory recursively
    public func listRecursive(path: String, maxDepth: Int = Int.max) async -> ListResult {
        guard isPathSafe(path) else {
            return ListResult(
                path: path,
                success: false,
                error: "Path traversal detected: \(path)"
            )
        }
        
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            return ListResult(
                path: path,
                success: false,
                error: "Path does not exist: \(path)"
            )
        }
        
        var allItems: [ListedItem] = []
        var totalSize: Int64 = 0
        
        await listRecursiveHelper(path: path, basePath: path, currentDepth: 0, maxDepth: maxDepth, items: &allItems, totalSize: &totalSize)
        
        allItems = sortItems(allItems)
        
        return ListResult(
            path: path,
            success: true,
            items: allItems,
            totalCount: allItems.count,
            totalSize: totalSize,
            truncated: config.maxItems > 0 && allItems.count > config.maxItems
        )
    }
    
    private func listRecursiveHelper(path: String, basePath: String, currentDepth: Int, maxDepth: Int, items: inout [ListedItem], totalSize: inout Int64) async {
        guard currentDepth < maxDepth else { return }
        
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            
            for name in contents {
                // Skip hidden files if configured
                if !config.includeHidden && name.hasPrefix(".") {
                    continue
                }
                
                let itemPath = (path as NSString).appendingPathComponent(name)
                
                do {
                    let item = try createListedItem(name: name, path: itemPath, basePath: basePath)
                    items.append(item)
                    totalSize += item.size
                    
                    // Recurse into directories
                    if item.isDirectory {
                        await listRecursiveHelper(
                            path: itemPath,
                            basePath: basePath,
                            currentDepth: currentDepth + 1,
                            maxDepth: maxDepth,
                            items: &items,
                            totalSize: &totalSize
                        )
                    }
                } catch {
                    // Skip items we can't access
                    continue
                }
            }
        } catch {
            // Ignore directory access errors during recursion
        }
    }
    
    private func createListedItem(name: String, path: String, basePath: String) throws -> ListedItem {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: path)
        
        let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
        let size = (attributes[.size] as? Int64) ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date()
        let createdAt = (attributes[.creationDate] as? Date) ?? Date()
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0
        
        let permString = formatPermissions(permissions)
        let ext = isDirectory ? nil : (name as NSString).pathExtension.isEmpty ? nil : (name as NSString).pathExtension
        
        let relativePath = config.fullPath ? path : path.replacingOccurrences(of: basePath + "/", with: "")
        
        return ListedItem(
            name: name,
            path: relativePath,
            isDirectory: isDirectory,
            size: size,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            permissions: permString,
            extension_: ext
        )
    }
    
    private func formatPermissions(_ permissions: Int) -> String {
        let r = (permissions & 0b100000000) != 0 ? "r" : "-"
        let w = (permissions & 0b010000000) != 0 ? "w" : "-"
        let x = (permissions & 0b001000000) != 0 ? "x" : "-"
        return r + w + x + "------"
    }
    
    private func sortItems(_ items: [ListedItem]) -> [ListedItem] {
        let sorted: [ListedItem]
        
        switch config.sortBy {
        case .name:
            sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateModified:
            sorted = items.sorted { $0.modifiedAt > $1.modifiedAt }
        case .dateCreated:
            sorted = items.sorted { $0.createdAt > $1.createdAt }
        case .size:
            sorted = items.sorted { $0.size > $1.size }
        case .type:
            sorted = items.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        
        return config.sortOrder == .ascending ? sorted : sorted.reversed()
    }
    
    /// Check if path is safe (no path traversal)
    private func isPathSafe(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.contains("..")
    }
}

/// Options for list_directory tool
public struct ListDirectoryOptions: Sendable {
    /// Include hidden files
    public let includeHidden: Bool
    
    /// Sort by attribute
    public enum SortBy: String, Sendable {
        case name
        case dateModified = "date_modified"
        case dateCreated = "date_created"
        case size
        case type
    }
    
    public let sortBy: SortBy
    
    /// Sort order
    public enum SortOrder: String, Sendable {
        case asc, desc
    }
    
    public let order: SortOrder
    
    /// Maximum items to return
    public let maxItems: Int
    
    /// Include file statistics
    public let includeStats: Bool
    
    public init(
        includeHidden: Bool = false,
        sortBy: SortBy = .name,
        order: SortOrder = .asc,
        maxItems: Int = 0,
        includeStats: Bool = false
    ) {
        self.includeHidden = includeHidden
        self.sortBy = sortBy
        self.order = order
        self.maxItems = maxItems
        self.includeStats = includeStats
    }
}
