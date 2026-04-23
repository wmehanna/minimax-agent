import Foundation

/// A thread-safe token bucket rate limiter.
///
/// The token bucket algorithm allows burst traffic up to the bucket capacity while
/// enforcing a long-term average rate. Tokens are added to the bucket at a constant
/// rate; each operation consumes tokens. If no tokens are available, the caller waits.
///
/// Example:
/// ```swift
/// let bucket = TokenBucket(capacity: 10, refillRate: 5.0) // 10 tokens max, 5 per second
/// // Wait for a token before making a request
/// try await bucket.acquire()
/// ```
public actor TokenBucket {

    // MARK: - Configuration

    /// Configuration for a token bucket
    public struct Config: Sendable {
        /// Maximum number of tokens in the bucket
        public let capacity: Int

        /// Rate at which tokens are added per second
        public let refillRate: Double

        /// Whether to allow bursting (consuming multiple tokens at once)
        public let allowBurst: Bool

        /// Maximum tokens that can be consumed in a single acquire call
        public let maxConsumeAtOnce: Int

        public init(
            capacity: Int = 10,
            refillRate: Double = 5.0,
            allowBurst: Bool = true,
            maxConsumeAtOnce: Int = 1
        ) {
            self.capacity = capacity
            self.refillRate = refillRate
            self.allowBurst = allowBurst
            self.maxConsumeAtOnce = maxConsumeAtOnce
        }

        /// Standard configuration for API rate limiting (e.g., 60 requests/minute)
        public static let standard = Config(capacity: 60, refillRate: 1.0)

        /// High capacity for bursty workloads
        public static let bursty = Config(capacity: 100, refillRate: 10.0)

        /// Conservative configuration for strict rate limits
        public static let conservative = Config(capacity: 5, refillRate: 0.5)
    }

    // MARK: - Errors

    /// Error types for token bucket operations
    public enum TokenBucketError: Error, LocalizedError, Equatable {
        /// Tried to consume more tokens than the maximum allowed per call
        case exceedsMaxConsume(requested: Int, maxAllowed: Int)

        /// The bucket does not have enough tokens and wait was not allowed
        case insufficientTokens(available: Int, requested: Int)

        public var errorDescription: String? {
            switch self {
            case .exceedsMaxConsume(let requested, let max):
                return "Requested \(requested) tokens but max consume at once is \(max)"
            case .insufficientTokens(let available, let requested):
                return "Insufficient tokens: requested \(requested), available \(available)"
            }
        }
    }

    // MARK: - State

    /// Current state of the bucket (for inspection)
    public struct State: Sendable {
        /// Current number of tokens available
        public let availableTokens: Int

        /// Maximum capacity of the bucket
        public let capacity: Int

        /// Tokens added per second
        public let refillRate: Double

        /// Unix timestamp when tokens were last refilled
        public let lastRefillTime: Date

        /// Time until the next token is added
        public var timeUntilNextToken: TimeInterval {
            guard refillRate > 0 else { return .infinity }
            let timeSinceRefill = Date().timeIntervalSince(lastRefillTime)
            let tokensPerInterval = 1.0 / refillRate
            return max(0, tokensPerInterval - (timeSinceRefill.truncatingRemainder(dividingBy: tokensPerInterval)))
        }

        /// Fill percentage (0.0 to 1.0)
        public var fillPercentage: Double {
            Double(availableTokens) / Double(capacity)
        }
    }

    // MARK: - Properties

    private let config: Config
    private var tokens: Double
    private var lastRefillTime: Date

    // MARK: - Initialization

    /// Create a new token bucket
    /// - Parameters:
    ///   - config: Configuration for the bucket
    ///   - initialTokens: Initial number of tokens (defaults to full capacity)
    public init(config: Config = .standard, initialTokens: Double? = nil) {
        self.config = config
        self.tokens = initialTokens ?? Double(config.capacity)
        self.lastRefillTime = Date()
    }

    /// Convenience initializer with capacity and refill rate
    /// - Parameters:
    ///   - capacity: Maximum tokens in the bucket
    ///   - refillRate: Tokens added per second
    public init(capacity: Int, refillRate: Double) {
        self.init(config: Config(capacity: capacity, refillRate: refillRate))
    }

    // MARK: - Public Methods

    /// Acquire a token, waiting if necessary until one is available.
    ///
    /// If tokens are available, returns immediately. If not, waits until a token
    /// is added and then returns.
    ///
    /// - Parameter count: Number of tokens to acquire (default: 1)
    /// - Throws: TokenBucketError if count exceeds maxConsumeAtOnce
    public func acquire(count: Int = 1) async throws {
        try await acquire(count: count, timeout: .infinity)
    }

    /// Acquire a token, with an optional timeout.
    ///
    /// - Parameters:
    ///   - count: Number of tokens to acquire
    ///   - timeout: Maximum time to wait for tokens to become available
    /// - Throws: TokenBucketError.timeout if timeout expires
    /// - Throws: TokenBucketError.exceedsMaxConsume if count > maxConsumeAtOnce
    public func acquire(count: Int = 1, timeout: TimeInterval) async throws {
        guard count <= config.maxConsumeAtOnce else {
            throw TokenBucketError.exceedsMaxConsume(requested: count, maxAllowed: config.maxConsumeAtOnce)
        }

        let deadline = timeout.isFinite ? Date().addingTimeInterval(timeout) : Date.distantFuture

        while true {
            refill()

            if tokens >= Double(count) {
                tokens -= Double(count)
                return
            }

            // Calculate wait time for the required tokens
            let tokensNeeded = Double(count) - tokens
            let tokensPerSecond = config.refillRate
            guard tokensPerSecond > 0 else {
                // No refill rate, can never acquire
                throw TokenBucketError.insufficientTokens(available: Int(tokens), requested: count)
            }

            let waitTime = tokensNeeded / tokensPerSecond
            let waitDeadline = Date().addingTimeInterval(waitTime)

            if Date() >= deadline {
                throw TokenBucketError.insufficientTokens(available: Int(tokens), requested: count)
            }

            // Wait until either tokens are available or timeout
            let actualWait = min(waitTime, deadline.timeIntervalSinceNow)
            if actualWait > 0 {
                try await Task.sleep(nanoseconds: UInt64(actualWait * 1_000_000_000))
            }
        }
    }

    /// Try to acquire a token without waiting.
    ///
    /// - Parameter count: Number of tokens to acquire
    /// - Returns: True if tokens were acquired, false otherwise
    @discardableResult
    public func tryAcquire(count: Int = 1) -> Bool {
        guard count <= config.maxConsumeAtOnce else {
            return false
        }

        refill()

        if tokens >= Double(count) {
            tokens -= Double(count)
            return true
        }

        return false
    }

    /// Get the current state of the bucket.
    public func state() -> State {
        refill()
        return State(
            availableTokens: Int(tokens),
            capacity: config.capacity,
            refillRate: config.refillRate,
            lastRefillTime: lastRefillTime
        )
    }

    /// Wait until at least the specified number of tokens are available.
    /// This is useful for rate-limiting bursts.
    ///
    /// - Parameter count: Minimum number of tokens needed
    /// - Parameter timeout: Maximum time to wait
    public func waitForTokens(_ count: Int, timeout: TimeInterval = .infinity) async throws {
        guard count <= config.capacity else {
            throw TokenBucketError.exceedsMaxConsume(requested: count, maxAllowed: config.capacity)
        }

        let deadline = timeout.isFinite ? Date().addingTimeInterval(timeout) : Date.distantFuture

        while true {
            refill()

            if tokens >= Double(count) {
                return
            }

            let tokensNeeded = Double(count) - tokens
            let tokensPerSecond = config.refillRate
            guard tokensPerSecond > 0 else { continue }

            let waitTime = tokensNeeded / tokensPerSecond
            let actualWait = min(waitTime, deadline.timeIntervalSinceNow)

            if Date() >= deadline {
                throw TokenBucketError.insufficientTokens(available: Int(tokens), requested: count)
            }

            if actualWait > 0 {
                try await Task.sleep(nanoseconds: UInt64(actualWait * 1_000_000_000))
            }
        }
    }

    /// Reset the bucket to full capacity.
    public func reset() {
        tokens = Double(config.capacity)
        lastRefillTime = Date()
    }

    /// Manually add tokens to the bucket (e.g., for testing or special cases).
    /// Does not exceed capacity.
    ///
    /// - Parameter count: Number of tokens to add
    public func addTokens(_ count: Int) {
        tokens = min(Double(count) + tokens, Double(config.capacity))
    }

    // MARK: - Private Methods

    /// Refill tokens based on elapsed time since last refill.
    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)

        guard elapsed > 0 && config.refillRate > 0 else { return }

        let tokensToAdd = elapsed * config.refillRate
        tokens = min(tokens + tokensToAdd, Double(config.capacity))
        lastRefillTime = now
    }
}



// MARK: - Sendable Conformance (for use with Task)

extension TokenBucket: @unchecked Sendable {}

// MARK: - Convenience Factory

extension TokenBucket {
    /// Create a bucket configured for a specific API rate limit.
    ///
    /// - Parameters:
    ///   - requestsPerMinute: Maximum requests per minute
    ///   - burstSize: Maximum burst size (defaults to requestsPerMinute)
    public static func forAPIRateLimit(requestsPerMinute: Int, burstSize: Int? = nil) -> TokenBucket {
        let capacity = burstSize ?? requestsPerMinute
        let refillRate = Double(requestsPerMinute) / 60.0
        return TokenBucket(
            config: Config(
                capacity: capacity,
                refillRate: refillRate,
                allowBurst: true,
                maxConsumeAtOnce: min(10, capacity / 10)
            )
        )
    }
}
