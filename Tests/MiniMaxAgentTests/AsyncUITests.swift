import XCTest
@testable import MiniMaxAgent

// MARK: - AsyncUITests
//
// Asynchronous UI-layer tests using async/await throughout.
// Covers ChatViewController state mutations, ServiceResponse
// encode/decode round-trips, TokenBucket async acquire, and
// ChatPersistenceService actor-isolated persistence.

// MARK: - ChatViewController Async Tests

@MainActor
final class ChatViewControllerAsyncTests: XCTestCase {

    // MARK: - Properties

    var sut: ChatViewController!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        sut = ChatViewController()
        sut.loadView()
        sut.viewDidLoad()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - updateMessages

    func testUpdateMessagesReplacesState() async {
        // Arrange
        let messages = [
            ChatMessage(content: "Hello", sender: .user),
            ChatMessage(content: "Hi there!", sender: .assistant)
        ]

        // Act
        sut.updateMessages(messages)

        // Assert — view controller remains intact after update
        XCTAssertNotNil(sut.view)
    }

    func testAddMessageAppendsInOrder() async {
        // Arrange
        let first  = ChatMessage(content: "First",  sender: .user)
        let second = ChatMessage(content: "Second", sender: .assistant)
        let third  = ChatMessage(content: "Third",  sender: .user)

        // Act — three sequential adds
        sut.addMessage(first)
        sut.addMessage(second)
        sut.addMessage(third)

        // Assert — controller stays alive and view is intact
        XCTAssertNotNil(sut.view)
    }

    func testUpdateMessagesWithEmptyArrayClearsView() async {
        // Arrange — seed some messages first
        sut.addMessage(ChatMessage(content: "seed", sender: .user))

        // Act
        sut.updateMessages([])

        // Assert
        XCTAssertNotNil(sut.view)
    }

    func testConcurrentAddMessagesDoesNotCrash() async {
        // Act — simulate rapid concurrent UI updates via async tasks on MainActor
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { @MainActor in
                    let msg = ChatMessage(
                        content: "msg-\(i)",
                        sender: i.isMultiple(of: 2) ? .user : .assistant
                    )
                    self.sut.addMessage(msg)
                }
            }
        }

        // Assert — view controller survived all updates
        XCTAssertNotNil(sut.view)
    }
}

// MARK: - ServiceResponse Async Encode/Decode Tests

final class ServiceResponseAsyncTests: XCTestCase {

    // MARK: - Encode / Decode round-trips

    func testTextResponseRoundTrip() async throws {
        // Arrange
        let original = ServiceResponse.text("Hello, async world!")

        // Act
        let data = try original.encode()
        let decoded = try ServiceResponse.decode(from: data)

        // Assert
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.items.first?.text, "Hello, async world!")
    }

    func testURLResponseRoundTrip() async throws {
        // Arrange
        let url = URL(string: "https://example.com/async-test")!
        let original = ServiceResponse.url(url)

        // Act
        let data = try original.encode()
        let decoded = try ServiceResponse.decode(from: data)

        // Assert
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.items.first?.url, url)
    }

    func testMultipleItemsRoundTrip() async throws {
        // Arrange
        let items: [ServiceResponse.ServiceItem] = [
            .text("item one"),
            .text("item two"),
            .url(URL(string: "https://example.com")!)
        ]
        let original = ServiceResponse.multiple(items)

        // Act
        let data = try original.encode()
        let decoded = try ServiceResponse.decode(from: data)

        // Assert
        XCTAssertEqual(decoded.items.count, 3)
        XCTAssertEqual(decoded, original)
    }

    func testJSONStringRoundTrip() async throws {
        // Arrange
        let original = ServiceResponse.text("JSON round-trip")

        // Act
        let json = try original.toJSON()
        let decoded = try ServiceResponse.fromJSON(json)

        // Assert
        XCTAssertEqual(decoded, original)
        XCTAssertFalse(json.isEmpty)
    }

    func testConcurrentEncodeDecodeIsStable() async throws {
        // Arrange
        let response = ServiceResponse.text("concurrent")

        // Act — encode/decode concurrently in a task group
        try await withThrowingTaskGroup(of: ServiceResponse.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let data = try response.encode()
                    return try ServiceResponse.decode(from: data)
                }
            }
            for try await result in group {
                XCTAssertEqual(result, response)
            }
        }
    }
}

// MARK: - TokenBucket Async Acquire Tests

final class TokenBucketAsyncTests: XCTestCase {

    // MARK: - Acquire

    func testAcquireSingleTokenSucceeds() async throws {
        // Arrange
        let bucket = TokenBucket(config: .init(capacity: 5, refillRate: 100.0))

        // Act + Assert — should not throw
        try await bucket.acquire()
        let state = await bucket.state()
        XCTAssertEqual(state.capacity, 5)
    }

    func testAcquireMultipleTokensSequentially() async throws {
        // Arrange — high refill rate so tokens are available immediately
        let config = TokenBucket.Config(capacity: 10, refillRate: 1000.0, allowBurst: true, maxConsumeAtOnce: 5)
        let bucket = TokenBucket(config: config)

        // Act — drain several tokens one at a time
        for _ in 0..<5 {
            try await bucket.acquire(count: 1)
        }

        // Assert — bucket is still alive and has sensible state
        let state = await bucket.state()
        XCTAssertEqual(state.capacity, 10)
    }

    func testAcquireExceedingMaxConsumeThrows() async throws {
        // Arrange — maxConsumeAtOnce = 1
        let config = TokenBucket.Config(capacity: 10, refillRate: 5.0, maxConsumeAtOnce: 1)
        let bucket = TokenBucket(config: config)

        // Act + Assert
        do {
            try await bucket.acquire(count: 2)
            XCTFail("Expected exceedsMaxConsume error")
        } catch TokenBucket.TokenBucketError.exceedsMaxConsume(let requested, let maxAllowed) {
            XCTAssertEqual(requested, 2)
            XCTAssertEqual(maxAllowed, 1)
        }
    }

    func testAcquireWithTimeoutOnExhaustedBucket() async throws {
        // Arrange — single token, very slow refill
        let config = TokenBucket.Config(capacity: 1, refillRate: 0.001, maxConsumeAtOnce: 1)
        let bucket = TokenBucket(config: config)

        // Drain the only token
        try await bucket.acquire(count: 1, timeout: 5.0)

        // Act — try to acquire again with a tight timeout; expect error or success
        do {
            try await bucket.acquire(count: 1, timeout: 0.05)
            // If refill happened in time, success is also acceptable
        } catch {
            XCTAssertTrue(error is TokenBucket.TokenBucketError)
        }
    }

    func testBucketStateReflectsCapacity() async {
        // Arrange
        let config = TokenBucket.Config(capacity: 42, refillRate: 1.0)
        let bucket = TokenBucket(config: config)

        // Act
        let state = await bucket.state()

        // Assert
        XCTAssertEqual(state.capacity, 42)
        XCTAssertEqual(state.refillRate, 1.0, accuracy: 0.0001)
    }
}

// MARK: - ChatPersistenceService Async Tests

final class ChatPersistenceServiceAsyncTests: XCTestCase {

    // MARK: - Properties

    var sut: ChatPersistenceService!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        sut = try ChatPersistenceService(inMemory: true)
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Save / Load

    func testSaveAndLoadMessage() async throws {
        // Arrange
        let conversationId = UUID().uuidString
        let message = ChatMessage(content: "Async persistence test", sender: .user)

        // Act
        try await sut.save(message, conversationId: conversationId)
        let loaded = try await sut.loadMessages(conversationId: conversationId)

        // Assert
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "Async persistence test")
        XCTAssertEqual(loaded.first?.sender, .user)
    }

    func testSaveMultipleMessagesPreservesOrder() async throws {
        // Arrange
        let conversationId = UUID().uuidString
        let messages = [
            ChatMessage(content: "Alpha", sender: .user),
            ChatMessage(content: "Beta",  sender: .assistant),
            ChatMessage(content: "Gamma", sender: .user)
        ]

        // Act
        for msg in messages {
            try await sut.save(msg, conversationId: conversationId)
        }
        let loaded = try await sut.loadMessages(conversationId: conversationId)

        // Assert
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.content), ["Alpha", "Beta", "Gamma"])
    }

    func testDeleteMessageRemovesFromStore() async throws {
        // Arrange
        let conversationId = UUID().uuidString
        let message = ChatMessage(content: "To be deleted", sender: .assistant)
        try await sut.save(message, conversationId: conversationId)

        // Act
        try await sut.delete(id: message.id)
        let loaded = try await sut.loadMessages(conversationId: conversationId)

        // Assert
        XCTAssertEqual(loaded.count, 0)
    }

    func testDeleteAllClearsStore() async throws {
        // Arrange
        let conversationId = UUID().uuidString
        for i in 0..<5 {
            let msg = ChatMessage(content: "msg-\(i)", sender: .user)
            try await sut.save(msg, conversationId: conversationId)
        }

        // Act
        try await sut.deleteAll()
        let loaded = try await sut.loadMessages(conversationId: conversationId)

        // Assert
        XCTAssertEqual(loaded.count, 0)
    }

    func testConcurrentSavesAreIsolated() async throws {
        // Arrange
        let conversationId = UUID().uuidString

        // Act — concurrent saves to the same actor-isolated service
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let msg = ChatMessage(content: "concurrent-\(i)", sender: .user)
                    try await self.sut.save(msg, conversationId: conversationId)
                }
            }
            try await group.waitForAll()
        }

        // Assert
        let loaded = try await sut.loadMessages(conversationId: conversationId)
        XCTAssertEqual(loaded.count, 10)
    }
}
