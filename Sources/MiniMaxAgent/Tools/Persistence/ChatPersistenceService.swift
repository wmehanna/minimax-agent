import Foundation
import SQLite

/// Service responsible for persisting chat messages to SQLite
public actor ChatPersistenceService {
    // MARK: - Table Definition

    private struct ChatMessageTable {
        static let table = Table("chat_messages")
        static let id = SQLite.Expression<String>("id")
        static let conversationId = SQLite.Expression<String>("conversation_id")
        static let content = SQLite.Expression<String>("content")
        static let sender = SQLite.Expression<String>("sender")
        static let timestamp = SQLite.Expression<Double>("timestamp")
        static let statusType = SQLite.Expression<String>("status_type")
        static let statusReason = SQLite.Expression<String?>("status_reason")
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
        self.table = ChatMessageTable.table
        try createTableIfNeeded()
    }

    /// Initialize with an in-memory database (useful for testing)
    public init(inMemory: Bool) throws {
        if inMemory {
            self.db = try Connection(.inMemory)
        } else {
            self.db = try Connection()
        }
        self.table = ChatMessageTable.table
        try createTableIfNeeded()
    }

    private func createTableIfNeeded() throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(ChatMessageTable.id, primaryKey: true)
            t.column(ChatMessageTable.conversationId)
            t.column(ChatMessageTable.content)
            t.column(ChatMessageTable.sender)
            t.column(ChatMessageTable.timestamp)
            t.column(ChatMessageTable.statusType)
            t.column(ChatMessageTable.statusReason)
        })

        // Composite index on conversation_id + timestamp for efficient message lookups
        try db.run(table.createIndex(
            ChatMessageTable.conversationId,
            ChatMessageTable.timestamp,
            ifNotExists: true
        ))
    }

    // MARK: - CRUD Operations

    /// Save a single chat message
    /// - Parameter message: The chat message to save
    /// - Parameter conversationId: The UUID string of the conversation this message belongs to
    public func save(_ message: ChatMessage, conversationId: String) throws {
        let statusType: String
        let statusReason: String?

        switch message.status {
        case .sending:
            statusType = "sending"
            statusReason = nil
        case .sent:
            statusType = "sent"
            statusReason = nil
        case .failed(let reason):
            statusType = "failed"
            statusReason = reason
        }

        let insert = table.insert(or: .replace,
            ChatMessageTable.id <- message.id.uuidString,
            ChatMessageTable.conversationId <- conversationId,
            ChatMessageTable.content <- message.content,
            ChatMessageTable.sender <- message.sender.rawValue,
            ChatMessageTable.timestamp <- message.timestamp.timeIntervalSince1970,
            ChatMessageTable.statusType <- statusType,
            ChatMessageTable.statusReason <- statusReason
        )
        try db.run(insert)
    }

    /// Save multiple chat messages in a batch
    /// - Parameter messages: The messages to save
    /// - Parameter conversationId: The UUID string of the conversation these messages belong to
    public func saveAll(_ messages: [ChatMessage], conversationId: String) throws {
        for message in messages {
            try save(message, conversationId: conversationId)
        }
    }

    /// Load all chat messages, ordered by timestamp ascending
    /// - Returns: An array of chat messages
    public func loadAll() throws -> [ChatMessage] {
        let query = table.order(ChatMessageTable.timestamp.asc)
        return try loadMessagesFromQuery(query)
    }

    /// Load all messages for a specific conversation, ordered by timestamp ascending
    /// - Parameter conversationId: The UUID string of the conversation
    /// - Returns: An array of chat messages for the conversation
    public func loadMessages(conversationId: String) throws -> [ChatMessage] {
        let query = table
            .filter(ChatMessageTable.conversationId == conversationId)
            .order(ChatMessageTable.timestamp.asc)
        return try loadMessagesFromQuery(query)
    }

    private func loadMessagesFromQuery(_ query: Table) throws -> [ChatMessage] {
        var messages: [ChatMessage] = []

        for row in try db.prepare(query) {
            guard let uuid = UUID(uuidString: row[ChatMessageTable.id]) else { continue }
            guard let sender = ChatMessage.Sender(rawValue: row[ChatMessageTable.sender]) else { continue }

            let status: ChatMessage.Status
            switch row[ChatMessageTable.statusType] {
            case "sending":
                status = .sending
            case "sent":
                status = .sent
            case "failed":
                status = .failed(row[ChatMessageTable.statusReason] ?? "Unknown error")
            default:
                status = .sent
            }

            let message = ChatMessage(
                id: uuid,
                content: row[ChatMessageTable.content],
                sender: sender,
                timestamp: Date(timeIntervalSince1970: row[ChatMessageTable.timestamp]),
                status: status
            )
            messages.append(message)
        }

        return messages
    }

    /// Load chat messages with a limit
    /// - Parameter limit: Maximum number of messages to load
    /// - Returns: An array of chat messages, most recent last
    public func loadRecent(limit: Int) throws -> [ChatMessage] {
        let query = table.order(ChatMessageTable.timestamp.desc).limit(limit)
        var messages: [ChatMessage] = []

        for row in try db.prepare(query) {
            guard let uuid = UUID(uuidString: row[ChatMessageTable.id]) else { continue }
            guard let sender = ChatMessage.Sender(rawValue: row[ChatMessageTable.sender]) else { continue }

            let status: ChatMessage.Status
            switch row[ChatMessageTable.statusType] {
            case "sending":
                status = .sending
            case "sent":
                status = .sent
            case "failed":
                status = .failed(row[ChatMessageTable.statusReason] ?? "Unknown error")
            default:
                status = .sent
            }

            let message = ChatMessage(
                id: uuid,
                content: row[ChatMessageTable.content],
                sender: sender,
                timestamp: Date(timeIntervalSince1970: row[ChatMessageTable.timestamp]),
                status: status
            )
            messages.append(message)
        }

        return messages.reversed()
    }

    /// Delete a chat message by ID
    /// - Parameter id: The UUID of the message to delete
    public func delete(id: UUID) throws {
        let message = table.filter(ChatMessageTable.id == id.uuidString)
        try db.run(message.delete())
    }

    /// Delete all chat messages
    public func deleteAll() throws {
        try db.run(table.delete())
    }

    /// Update the status of a message
    /// - Parameters:
    ///   - id: The UUID of the message to update
    ///   - status: The new status
    public func updateStatus(id: UUID, status: ChatMessage.Status) throws {
        let statusType: String
        let statusReason: String?

        switch status {
        case .sending:
            statusType = "sending"
            statusReason = nil
        case .sent:
            statusType = "sent"
            statusReason = nil
        case .failed(let reason):
            statusType = "failed"
            statusReason = reason
        }

        let message = table.filter(ChatMessageTable.id == id.uuidString)
        try db.run(message.update(
            ChatMessageTable.statusType <- statusType,
            ChatMessageTable.statusReason <- statusReason
        ))
    }

    /// Get the count of stored messages
    /// - Returns: The number of messages in the database
    public func count() throws -> Int {
        return try db.scalar(table.count)
    }

    /// Check if there are any stored messages
    /// - Returns: true if the database has messages
    public func hasMessages() throws -> Bool {
        return try count() > 0
    }
}

// MARK: - Convenience Extensions

extension ChatPersistenceService {
    /// Create a new instance using the default database path
    public static func createDefault() throws -> ChatPersistenceService {
        return try ChatPersistenceService()
    }

    /// Create a new in-memory instance (for testing or temporary use)
    public static func createInMemory() throws -> ChatPersistenceService {
        return try ChatPersistenceService(inMemory: true)
    }
}
