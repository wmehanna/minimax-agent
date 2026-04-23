import Foundation
import SQLite

/// Service responsible for persisting conversation metadata to SQLite
public actor ConversationPersistenceService {
    // MARK: - Table Definition

    private struct ConversationsTable {
        static let table = Table("conversations")
        static let id = SQLite.Expression<String>("id")
        static let title = SQLite.Expression<String>("title")
        static let createdAt = SQLite.Expression<Double>("created_at")
        static let updatedAt = SQLite.Expression<Double>("updated_at")
    }

    // MARK: - Properties

    private let db: Connection
    private let table: Table

    // MARK: - Initialization

    /// Initialize the persistence service with a database path
    /// - Parameter dbPath: Path to the SQLite database file. Defaults to "chat.sqlite3" in the Application Support directory.
    public init(dbPath: String? = nil) throws {
        let path: String
        if let dbPath = dbPath {
            path = dbPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("MiniMaxAgent", isDirectory: true)
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            path = appFolder.appendingPathComponent("chat.sqlite3").path
        }

        self.db = try Connection(path)
        self.table = ConversationsTable.table
        try createTableIfNeeded()
    }

    /// Initialize with an in-memory database (useful for testing)
    public init(inMemory: Bool) throws {
        if inMemory {
            self.db = try Connection(.inMemory)
        } else {
            self.db = try Connection()
        }
        self.table = ConversationsTable.table
        try createTableIfNeeded()
    }

    private func createTableIfNeeded() throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(ConversationsTable.id, primaryKey: true)
            t.column(ConversationsTable.title)
            t.column(ConversationsTable.createdAt)
            t.column(ConversationsTable.updatedAt)
        })
    }

    // MARK: - CRUD Operations

    /// Save a conversation (insert or replace)
    /// - Parameter conversation: The conversation to save
    public func save(_ conversation: Conversation) throws {
        let insert = table.insert(or: .replace,
            ConversationsTable.id <- conversation.id.uuidString,
            ConversationsTable.title <- conversation.title,
            ConversationsTable.createdAt <- conversation.createdAt.timeIntervalSince1970,
            ConversationsTable.updatedAt <- conversation.updatedAt.timeIntervalSince1970
        )
        try db.run(insert)
    }

    /// Save multiple conversations in a batch
    /// - Parameter conversations: The conversations to save
    public func saveAll(_ conversations: [Conversation]) throws {
        for conversation in conversations {
            try save(conversation)
        }
    }

    /// Load all conversations, ordered by updatedAt descending (most recent first)
    /// - Returns: An array of conversations
    public func loadAll() throws -> [Conversation] {
        let query = table.order(ConversationsTable.updatedAt.desc)
        return try loadFromQuery(query)
    }

    /// Load conversations with a limit
    /// - Parameter limit: Maximum number of conversations to load
    /// - Returns: An array of conversations, most recent first
    public func loadRecent(limit: Int) throws -> [Conversation] {
        let query = table.order(ConversationsTable.updatedAt.desc).limit(limit)
        return try loadFromQuery(query)
    }

    private func loadFromQuery(_ query: Table) throws -> [Conversation] {
        var conversations: [Conversation] = []
        for row in try db.prepare(query) {
            guard let uuid = UUID(uuidString: row[ConversationsTable.id]) else { continue }
            let conversation = Conversation(
                id: uuid,
                title: row[ConversationsTable.title],
                createdAt: Date(timeIntervalSince1970: row[ConversationsTable.createdAt]),
                updatedAt: Date(timeIntervalSince1970: row[ConversationsTable.updatedAt])
            )
            conversations.append(conversation)
        }
        return conversations
    }

    /// Load a single conversation by ID
    /// - Parameter id: The UUID of the conversation to load
    /// - Returns: The conversation if found, nil otherwise
    public func load(id: UUID) throws -> Conversation? {
        let query = table.filter(ConversationsTable.id == id.uuidString)
        for row in try db.prepare(query) {
            guard let uuid = UUID(uuidString: row[ConversationsTable.id]) else { continue }
            return Conversation(
                id: uuid,
                title: row[ConversationsTable.title],
                createdAt: Date(timeIntervalSince1970: row[ConversationsTable.createdAt]),
                updatedAt: Date(timeIntervalSince1970: row[ConversationsTable.updatedAt])
            )
        }
        return nil
    }

    /// Delete a conversation by ID
    /// - Parameter id: The UUID of the conversation to delete
    public func delete(id: UUID) throws {
        let conversation = table.filter(ConversationsTable.id == id.uuidString)
        try db.run(conversation.delete())
    }

    /// Delete all conversations
    public func deleteAll() throws {
        try db.run(table.delete())
    }

    /// Update the title of a conversation
    /// - Parameters:
    ///   - id: The UUID of the conversation to update
    ///   - title: The new title
    public func updateTitle(id: UUID, title: String) throws {
        let conversation = table.filter(ConversationsTable.id == id.uuidString)
        try db.run(conversation.update(
            ConversationsTable.title <- title,
            ConversationsTable.updatedAt <- Date().timeIntervalSince1970
        ))
    }

    /// Touch a conversation to update its updatedAt timestamp
    /// - Parameter id: The UUID of the conversation to touch
    public func touch(id: UUID) throws {
        let conversation = table.filter(ConversationsTable.id == id.uuidString)
        try db.run(conversation.update(
            ConversationsTable.updatedAt <- Date().timeIntervalSince1970
        ))
    }

    /// Get the count of stored conversations
    /// - Returns: The number of conversations in the database
    public func count() throws -> Int {
        return try db.scalar(table.count)
    }

    /// Check if there are any stored conversations
    /// - Returns: true if the database has conversations
    public func hasConversations() throws -> Bool {
        return try count() > 0
    }
}

// MARK: - Convenience Extensions

extension ConversationPersistenceService {
    /// Create a new instance using the default database path
    public static func createDefault() throws -> ConversationPersistenceService {
        return try ConversationPersistenceService()
    }

    /// Create a new in-memory instance (for testing or temporary use)
    public static func createInMemory() throws -> ConversationPersistenceService {
        return try ConversationPersistenceService(inMemory: true)
    }
}
