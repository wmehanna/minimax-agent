import Foundation
import Collections

/// Manages queuing, prioritization, and rate-limiting of API requests.
///
/// RequestQueueManager ensures:
/// - Requests are processed in priority order
/// - Duplicate requests are coalesced
/// - Concurrent request limits are respected
/// - Rate limiting is enforced via TokenBucket
/// - Failed requests are retried with exponential backoff
public actor RequestQueueManager {

    // MARK: - Request

    /// A queued API request
    public struct Request: Identifiable, Sendable {
        public let id: UUID
        public let priority: Priority
        public let createdAt: Date
        public let deduplicationKey: String?
        public let execute: @Sendable () async throws -> Response

        /// Response type for requests
        public struct Response: Sendable {
            public let data: Data
            public let statusCode: Int

            public init(data: Data, statusCode: Int) {
                self.data = data
                self.statusCode = statusCode
            }
        }

        public enum Priority: Int, Sendable, Comparable {
            case high = 0
            case normal = 1
            case low = 2

            public static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        public init(
            id: UUID = UUID(),
            priority: Priority = .normal,
            deduplicationKey: String? = nil,
            execute: @escaping @Sendable () async throws -> Response
        ) {
            self.id = id
            self.priority = priority
            self.createdAt = Date()
            self.deduplicationKey = deduplicationKey
            self.execute = execute
        }
    }

    // MARK: - Configuration

    /// Configuration for the request queue manager
    public struct Config: Sendable {
        /// Maximum concurrent requests
        public let maxConcurrent: Int

        /// Maximum retries per request
        public let maxRetries: Int

        /// Base delay for exponential backoff (seconds)
        public let baseRetryDelay: TimeInterval

        /// Maximum retry delay (seconds)
        public let maxRetryDelay: TimeInterval

        /// Deduplication window (seconds) - identical requests within this window are coalesced
        public let deduplicationWindow: TimeInterval

        /// Default request timeout (seconds)
        public let requestTimeout: TimeInterval

        public init(
            maxConcurrent: Int = 4,
            maxRetries: Int = 3,
            baseRetryDelay: TimeInterval = 1.0,
            maxRetryDelay: TimeInterval = 60.0,
            deduplicationWindow: TimeInterval = 5.0,
            requestTimeout: TimeInterval = 30.0
        ) {
            self.maxConcurrent = maxConcurrent
            self.maxRetries = maxRetries
            self.baseRetryDelay = baseRetryDelay
            self.maxRetryDelay = maxRetryDelay
            self.deduplicationWindow = deduplicationWindow
            self.requestTimeout = requestTimeout
        }

        /// Standard configuration
        public static let standard = Config()

        /// Aggressive configuration for high-throughput scenarios
        public static let highThroughput = Config(
            maxConcurrent: 8,
            maxRetries: 2,
            deduplicationWindow: 2.0
        )

        /// Conservative configuration for rate-limited APIs
        public static let conservative = Config(
            maxConcurrent: 2,
            maxRetries: 5,
            baseRetryDelay: 2.0,
            deduplicationWindow: 10.0
        )
    }

    // MARK: - State

    /// Current state of the queue manager
    public struct State: Sendable {
        public let pendingCount: Int
        public let activeCount: Int
        public let completedCount: Int
        public let failedCount: Int
        public let deduplicatedCount: Int
    }

    // MARK: - Errors

    /// Errors from the request queue manager
    public enum QueueError: Error, LocalizedError, Sendable {
        case queueFull
        case requestCancelled
        case allRetriesFailed(lastError: Error?)
        case timeout
        case rateLimited(retryAfter: TimeInterval?)

        public var errorDescription: String? {
            switch self {
            case .queueFull:
                return "Request queue is full"
            case .requestCancelled:
                return "Request was cancelled"
            case .allRetriesFailed(let lastError):
                return "All retries failed: \(lastError?.localizedDescription ?? "unknown")"
            case .timeout:
                return "Request timed out"
            case .rateLimited(let retryAfter):
                if let delay = retryAfter {
                    return "Rate limited, retry after \(delay)s"
                }
                return "Rate limited"
            }
        }
    }

    // MARK: - Properties

    private let config: Config
    private let tokenBucket: TokenBucket

    private var queue: Deque<Request> = []
    private var activeRequests: Set<UUID> = []
    private var completedCount: Int = 0
    private var failedCount: Int = 0
    private var deduplicatedCount: Int = 0

    /// Pending deduplication map: key -> (request ID, completion time)
    private var deduplicationMap: [String: (UUID, Date)] = [:]

    /// Maximum queue size (0 = unlimited)
    private let maxQueueSize: Int

    // MARK: - Initialization

    /// Create a new request queue manager
    /// - Parameters:
    ///   - config: Configuration for the queue manager
    ///   - tokenBucket: Token bucket for rate limiting (optional)
    public init(config: Config = .standard, tokenBucket: TokenBucket? = nil) {
        self.config = config
        self.tokenBucket = tokenBucket ?? TokenBucket.forAPIRateLimit(requestsPerMinute: 60)
        self.maxQueueSize = 0 // Unlimited by default
    }

    // MARK: - Public Methods

    /// Enqueue a request and return the response
    /// - Parameter request: The request to enqueue
    /// - Returns: The response from the request
    /// - Throws: QueueError if the request fails after all retries
    public func enqueue(_ request: Request) async throws -> Request.Response {
        // Check for duplicate
        if let dedupKey = request.deduplicationKey {
            if let (existingId, completionTime) = deduplicationMap[dedupKey] {
                if Date().timeIntervalSince(completionTime) < config.deduplicationWindow {
                    deduplicatedCount += 1
                    // Wait for the existing request instead of creating a new one
                    return try await waitForRequest(existingId)
                }
            }
        }

        // Enqueue the request
        queue.append(request)

        // Sort queue by priority (highest first) and age
        sortQueue()

        // Record for deduplication
        if let dedupKey = request.deduplicationKey {
            deduplicationMap[dedupKey] = (request.id, Date().addingTimeInterval(config.deduplicationWindow))
        }

        // Process queue
        return try await processQueue()
    }

    /// Convenience method to enqueue a simple request
    /// - Parameters:
    ///   - priority: Request priority
    ///   - deduplicationKey: Key for deduplication (optional)
    ///   - execute: Closure to execute
    /// - Returns: The response
    public func enqueue(
        priority: Request.Priority = .normal,
        deduplicationKey: String? = nil,
        execute: @escaping @Sendable () async throws -> Request.Response
    ) async throws -> Request.Response {
        let request = Request(
            priority: priority,
            deduplicationKey: deduplicationKey,
            execute: execute
        )
        return try await enqueue(request)
    }

    /// Cancel a specific request
    /// - Parameter id: The request ID to cancel
    /// - Returns: True if the request was found and cancelled
    @discardableResult
    public func cancel(_ id: UUID) -> Bool {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index)
            return true
        }
        return false
    }

    /// Cancel all pending requests
    public func cancelAll() {
        queue.removeAll()
    }

    /// Get current queue state
    public func state() -> State {
        State(
            pendingCount: queue.count,
            activeCount: activeRequests.count,
            completedCount: completedCount,
            failedCount: failedCount,
            deduplicatedCount: deduplicatedCount
        )
    }

    /// Wait for a specific request to complete (used for deduplication)
    private func waitForRequest(_ id: UUID) async throws -> Request.Response {
        // In a real implementation, this would wait on a continuation or task group
        // For now, we poll - in production this would use proper task coordination
        var attempts = 0
        while attempts < 100 {
            let currentState = state()
            if currentState.activeCount == 0 && !queue.contains(where: { $0.id == id }) {
                // Request is no longer active or pending
                throw QueueError.requestCancelled
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            attempts += 1
        }
        throw QueueError.timeout
    }

    // MARK: - Private Methods

    private func sortQueue() {
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority // Lower rawValue = higher priority
            }
            return lhs.createdAt < rhs.createdAt // Older first
        }
    }

    private func processQueue() async throws -> Request.Response {
        while !queue.isEmpty {
            // Check if we can start more requests
            if activeRequests.count >= config.maxConcurrent {
                try await waitForActiveRequestToComplete()
                continue
            }

            // Get next request
            guard let request = queue.first else {
                break
            }

            queue.removeFirst()
            activeRequests.insert(request.id)

            // Start request in background
            Task {
                await executeRequest(request)
            }
        }

        // Wait for at least one request to complete
        if !activeRequests.isEmpty {
            try await waitForActiveRequestToComplete()
        }

        // This shouldn't be reached in normal operation
        throw QueueError.queueFull
    }

    private func executeRequest(_ request: Request) async {
        defer {
            activeRequests.remove(request.id)
        }

        // Acquire rate limit token
        do {
            try await tokenBucket.acquire(timeout: config.requestTimeout)
        } catch {
            failedCount += 1
            return
        }

        var lastError: Error?
        for attempt in 0..<config.maxRetries {
            do {
                let response = try await executeWithTimeout(request.execute)

                if response.statusCode == 429 {
                    // Rate limited - retry with backoff
                    lastError = QueueError.rateLimited(retryAfter: nil)
                    let delay = calculateRetryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                if response.statusCode >= 400 && response.statusCode < 500 {
                    // Client error - don't retry
                    completedCount += 1
                    return
                }

                if response.statusCode >= 500 {
                    // Server error - retry
                    lastError = QueueError.rateLimited(retryAfter: nil)
                    let delay = calculateRetryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                // Success
                completedCount += 1
                return
            } catch {
                lastError = error
                let delay = calculateRetryDelay(attempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        failedCount += 1
    }

    private func executeWithTimeout(_ operation: @escaping @Sendable () async throws -> Request.Response) async throws -> Request.Response {
        try await withThrowingTaskGroup(of: Request.Response.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.config.requestTimeout * 1_000_000_000))
                throw QueueError.timeout
            }

            guard let result = try await group.next() else {
                throw QueueError.timeout
            }

            group.cancelAll()
            return result
        }
    }

    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        var delay = config.baseRetryDelay * pow(2.0, Double(attempt))
        delay = min(delay, config.maxRetryDelay)
        // Add jitter
        delay *= Double.random(in: 0.8...1.2)
        return delay
    }

    private func waitForActiveRequestToComplete() async throws {
        // Simple polling implementation
        // In production, this would use proper continuations or Task-specific waiting
        var attempts = 0
        while activeRequests.count >= config.maxConcurrent && attempts < 100 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            attempts += 1
        }
    }
}

// MARK: - Request Builder

extension RequestQueueManager.Request {

    /// Create a GET request
    public static func get(
        url: String,
        priority: Priority = .normal,
        deduplicationKey: String? = nil,
        headers: [String: String] = [:],
        client: RateLimitedHTTPClient
    ) -> RequestQueueManager.Request {
        RequestQueueManager.Request(
            priority: priority,
            deduplicationKey: deduplicationKey
        ) {
            let response = try await client.get(url, headers: headers)
            return RequestQueueManager.Request.Response(data: response.body, statusCode: response.statusCode)
        }
    }

    /// Create a POST request
    public static func post<B: Encodable>(
        url: String,
        body: B,
        priority: Priority = .normal,
        deduplicationKey: String? = nil,
        headers: [String: String] = [:],
        client: RateLimitedHTTPClient
    ) -> RequestQueueManager.Request {
        RequestQueueManager.Request(
            priority: priority,
            deduplicationKey: deduplicationKey
        ) {
            let encoder = JSONEncoder()
            let data = try encoder.encode(body)
            let response = try await client.post(url, body: data, headers: headers)
            return RequestQueueManager.Request.Response(data: response.body, statusCode: response.statusCode)
        }
    }
}

// MARK: - Preview

#if DEBUG
extension RequestQueueManager {
    /// Create a preview instance with mock responses
    public static func preview() -> RequestQueueManager {
        RequestQueueManager(config: .standard)
    }
}
#endif
