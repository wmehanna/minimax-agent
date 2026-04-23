import AppKit
import Foundation
import UniformTypeIdentifiers

/// Tool for user-initiated file selection and operations.
/// Provides full disk access through NSOpenPanel/NSSavePanel for sandboxed apps.
public actor UserSelectedFileTool {
    // MARK: - Bookmark Storage

    /// Stores security-scoped bookmarks for persistent file access
    private struct BookmarkEntry: Codable {
        let bookmarkData: Data
        let path: String
        let lastAccessed: Date
    }

    private static let bookmarkKey = "UserSelectedFileBookmarks"
    private static var activeSecurityScopes: [URL: Bool] = [:]

    // MARK: - Result Types

    /// Result of a user file selection operation
    public struct SelectionResult: Sendable {
        public let success: Bool
        public let filePath: String?
        public let error: String?
        public let bookmarkCreated: Bool

        public init(success: Bool, filePath: String? = nil, error: String? = nil, bookmarkCreated: Bool = false) {
            self.success = success
            self.filePath = filePath
            self.error = error
            self.bookmarkCreated = bookmarkCreated
        }
    }

    /// Result of a read operation on a user-selected file
    public struct ReadResult: Sendable {
        public let success: Bool
        public let content: String?
        public let error: String?

        public init(success: Bool, content: String? = nil, error: String? = nil) {
            self.success = success
            self.content = content
            self.error = error
        }
    }

    /// Result of a write operation on a user-selected file
    public struct WriteResult: Sendable {
        public let success: Bool
        public let bytesWritten: Int64
        public let error: String?

        public init(success: Bool, bytesWritten: Int64 = 0, error: String? = nil) {
            self.success = success
            self.bytesWritten = bytesWritten
            self.error = error
        }
    }

    // MARK: - File Selection

    /// Present an NSOpenPanel for the user to select a file for reading
    /// - Parameters:
    ///   - allowedContentTypes: Allowed UTI content types (nil for all files)
    ///   - canChooseDirectories: Whether directories can be selected
    ///   - canChooseFiles: Whether files can be selected (default: true)
    ///   - prompt: The open button title
    /// - Returns: SelectionResult with the selected file path
    @MainActor
    public func selectFile(
        allowedContentTypes: [String]? = nil,
        canChooseDirectories: Bool = false,
        canChooseFiles: Bool = true,
        prompt: String = "Open"
    ) -> SelectionResult {
        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = "Select a file to read"

        if let types = allowedContentTypes {
            panel.allowedContentTypes = types.compactMap { UTType($0) }
        }

        let response = panel.runModal()
        let selectedURL = panel.url

        guard response == .OK, let url = selectedURL else {
            return SelectionResult(success: false, error: "No file selected")
        }

        // Create security-scoped bookmark for persistent access
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Store the bookmark
            try saveBookmark(bookmarkData: bookmarkData, path: url.path)

            return SelectionResult(
                success: true,
                filePath: url.path,
                bookmarkCreated: true
            )
        } catch {
            // If bookmark creation fails, still return the path but without persistent access
            return SelectionResult(
                success: true,
                filePath: url.path,
                bookmarkCreated: false
            )
        }
    }

    /// Present an NSSavePanel for the user to select a save location
    /// - Parameters:
    ///   - suggestedName: Suggested file name
    ///   - allowedContentTypes: Allowed UTI content types
    ///   - prompt: The save button title
    /// - Returns: SelectionResult with the selected file path
    @MainActor
    public func selectSaveLocation(
        suggestedName: String? = nil,
        allowedContentTypes: [String]? = nil,
        prompt: String = "Save"
    ) -> SelectionResult {
        let panel = NSSavePanel()
        panel.prompt = prompt
        panel.message = "Choose where to save the file"

        if let name = suggestedName {
            panel.nameFieldStringValue = name
        }

        if let types = allowedContentTypes, let first = types.first {
            panel.allowedContentTypes = [UTType(first) ?? .data]
        }

        let response = panel.runModal()
        let selectedURL = panel.url

        guard response == .OK, let url = selectedURL else {
            return SelectionResult(success: false, error: "No save location selected")
        }

        // Create security-scoped bookmark for persistent access
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Store the bookmark
            try saveBookmark(bookmarkData: bookmarkData, path: url.path)

            return SelectionResult(
                success: true,
                filePath: url.path,
                bookmarkCreated: true
            )
        } catch {
            return SelectionResult(
                success: true,
                filePath: url.path,
                bookmarkCreated: false
            )
        }
    }

    // MARK: - File Reading

    /// Read content from a user-selected file using security-scoped access
    /// - Parameters:
    ///   - path: Path to the file
    ///   - encoding: String encoding to use (nil for auto-detect)
    /// - Returns: ReadResult with the file content
    public func read(path: String, encoding: String.Encoding? = nil) -> ReadResult {
        let url = URL(fileURLWithPath: path)

        // Try to start accessing the security-scoped resource
        let accessed = url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            let content: String
            if let enc = encoding {
                guard let str = String(data: data, encoding: enc) else {
                    return ReadResult(success: false, error: "Could not decode file with specified encoding")
                }
                content = str
            } else {
                // Try UTF-8 first
                if let str = String(data: data, encoding: .utf8) {
                    content = str
                } else if let str = String(data: data, encoding: .isoLatin1) {
                    content = str
                } else {
                    return ReadResult(success: false, error: "Could not detect file encoding")
                }
            }

            return ReadResult(success: true, content: content)
        } catch {
            return ReadResult(success: false, error: error.localizedDescription)
        }
    }

    /// Read from a previously bookmarked file (persistent access)
    /// - Parameters:
    ///   - path: Path to the bookmarked file
    ///   - encoding: String encoding to use (nil for auto-detect)
    /// - Returns: ReadResult with the file content
    public func readBookmarked(path: String, encoding: String.Encoding? = nil) -> ReadResult {
        guard let bookmarkData = loadBookmark(for: path) else {
            // Fall back to regular read
            return read(path: path, encoding: encoding)
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, try to refresh or re-prompt
                return ReadResult(success: false, error: "Bookmark is stale. Please re-select the file.")
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)

            let content: String
            if let enc = encoding {
                guard let str = String(data: data, encoding: enc) else {
                    return ReadResult(success: false, error: "Could not decode file with specified encoding")
                }
                content = str
            } else if let str = String(data: data, encoding: .utf8) {
                content = str
            } else if let str = String(data: data, encoding: .isoLatin1) {
                content = str
            } else {
                return ReadResult(success: false, error: "Could not detect file encoding")
            }

            return ReadResult(success: true, content: content)
        } catch {
            return ReadResult(success: false, error: error.localizedDescription)
        }
    }

    // MARK: - File Writing

    /// Write content to a user-selected file using security-scoped access
    /// - Parameters:
    ///   - path: Path to the file
    ///   - content: Content to write
    ///   - encoding: String encoding to use
    ///   - atomically: Whether to write atomically
    /// - Returns: WriteResult with the write status
    public func write(
        path: String,
        content: String,
        encoding: String.Encoding = .utf8,
        atomically: Bool = true
    ) -> WriteResult {
        let url = URL(fileURLWithPath: path)

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            guard let data = content.data(using: encoding) else {
                return WriteResult(success: false, error: "Could not encode content")
            }

            try data.write(to: url, options: atomically ? .atomic : [])

            return WriteResult(success: true, bytesWritten: Int64(data.count))
        } catch {
            return WriteResult(success: false, error: error.localizedDescription)
        }
    }

    /// Write to a previously bookmarked file (persistent access)
    /// - Parameters:
    ///   - path: Path to the bookmarked file
    ///   - content: Content to write
    ///   - encoding: String encoding to use
    ///   - atomically: Whether to write atomically
    /// - Returns: WriteResult with the write status
    public func writeBookmarked(
        path: String,
        content: String,
        encoding: String.Encoding = .utf8,
        atomically: Bool = true
    ) -> WriteResult {
        guard let bookmarkData = loadBookmark(for: path) else {
            return WriteResult(success: false, error: "No bookmark found. Please re-select the file.")
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                return WriteResult(success: false, error: "Bookmark is stale. Please re-select the file.")
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = content.data(using: encoding) else {
                return WriteResult(success: false, error: "Could not encode content")
            }

            try data.write(to: url, options: atomically ? .atomic : [])

            return WriteResult(success: true, bytesWritten: Int64(data.count))
        } catch {
            return WriteResult(success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Bookmark Management

    /// Save a security-scoped bookmark to persistent storage
    private nonisolated func saveBookmark(bookmarkData: Data, path: String) throws {
        let defaults = UserDefaults.standard
        var bookmarks = loadAllBookmarks()

        // Remove old bookmark for this path if exists
        bookmarks.removeAll { $0.path == path }

        let entry = BookmarkEntry(
            bookmarkData: bookmarkData,
            path: path,
            lastAccessed: Date()
        )
        bookmarks.append(entry)

        let data = try JSONEncoder().encode(bookmarks)
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    /// Load bookmark data for a specific path
    private nonisolated func loadBookmark(for path: String) -> Data? {
        let bookmarks = loadAllBookmarks()
        return bookmarks.first { $0.path == path }?.bookmarkData
    }

    /// Load all stored bookmarks
    private nonisolated func loadAllBookmarks() -> [BookmarkEntry] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([BookmarkEntry].self, from: data)
        } catch {
            return []
        }
    }

    /// Clear all stored bookmarks
    public nonisolated func clearAllBookmarks() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    /// List all bookmarked paths
    public nonisolated func listBookmarkedPaths() -> [String] {
        return loadAllBookmarks().map { $0.path }
    }
}
