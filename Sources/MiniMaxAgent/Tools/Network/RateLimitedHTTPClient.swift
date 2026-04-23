import Foundation

/// Tool for making HTTP requests with automatic handling of 429 (Too Many Requests) responses.
/// Parses the Retry-After header and waits before retrying.
public actor RateLimitedHTTPClient {

    // MARK: - HTTP Response

    /// Result of an HTTP request
    public struct HTTPResponse: Sendable, Equatable {
        /// HTTP status code
        public let statusCode: Int

        /// Response headers
        public let headers: [String: String]

        /// Response body as Data
        public let body: Data

        /// Response body as String (if valid UTF-8)
        public var bodyString: String? {
            String(data: body, encoding: .utf8)
        }

        /// Whether the request was successful (2xx status codes)
        public var isSuccess: Bool {
            statusCode >= 200 && statusCode < 300
        }

        /// Whether the response indicates rate limiting (429)
        public var isRateLimited: Bool {
            statusCode == 429
        }

        /// The Retry-After value in seconds (nil if not present or not parseable)
        public var retryAfterSeconds: Int? {
            guard let value = headers["Retry-After"] ?? headers["retry-after"] else {
                return nil
            }
            // Could be HTTP-date or delta-seconds
            if let seconds = Int(value) {
                return seconds
            }
            // Try parsing as HTTP-date (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(abbreviation: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) {
                let interval = date.timeIntervalSinceNow
                return interval > 0 ? Int(interval) : nil
            }
            return nil
        }

        /// Extract rate limit details from headers
        public var rateLimitInfo: RateLimitInfo? {
            let limit = headers["X-RateLimit-Limit"] ?? headers["x-rate-limit-limit"]
            let remaining = headers["X-RateLimit-Remaining"] ?? headers["x-rate-limit-remaining"]
            let reset = headers["X-RateLimit-Reset"] ?? headers["x-rate-limit-reset"]

            guard limit != nil || remaining != nil || reset != nil else {
                return nil
            }

            return RateLimitInfo(
                limit: limit.flatMap { Int($0) },
                remaining: remaining.flatMap { Int($0) },
                resetTimestamp: reset.flatMap { TimeInterval($0) }
            )
        }

        public init(statusCode: Int, headers: [String: String], body: Data) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    /// Rate limit information extracted from response headers
    public struct RateLimitInfo: Sendable, Equatable {
        /// The maximum number of requests allowed in the window
        public let limit: Int?

        /// The number of requests remaining in the current window
        public let remaining: Int?

        /// Unix timestamp when the rate limit resets
        public let resetTimestamp: TimeInterval?

        /// Human-readable reset time
        public var resetTime: String? {
            guard let reset = resetTimestamp else { return nil }
            let date = Date(timeIntervalSince1970: reset)
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
    }

    // MARK: - Configuration

    /// Configuration for rate-limited HTTP requests
    public struct Config: Sendable {
        /// Maximum number of retry attempts on 429 responses
        public let maxRetries: Int

        /// Default delay when Retry-After header is not present (in seconds)
        public let defaultRetryDelay: TimeInterval

        /// Maximum retry delay cap (in seconds)
        public let maxRetryDelay: TimeInterval

        /// Initial base delay for exponential backoff
        public let baseDelay: TimeInterval

        /// Multiplier for exponential backoff
        public let backoffMultiplier: Double

        /// Jitter factor (0.0 to 1.0) for randomizing delays
        public let jitterFactor: Double

        /// Additional HTTP headers to include with every request
        public let defaultHeaders: [String: String]

        /// Request timeout (0 = no timeout)
        public let timeout: TimeInterval

        /// Whether to include rate limit info in errors
        public let includeRateLimitInfoInError: Bool

        public init(
            maxRetries: Int = 5,
            defaultRetryDelay: TimeInterval = 60.0,
            maxRetryDelay: TimeInterval = 3600.0,
            baseDelay: TimeInterval = 1.0,
            backoffMultiplier: Double = 2.0,
            jitterFactor: Double = 0.1,
            defaultHeaders: [String: String] = [:],
            timeout: TimeInterval = 30.0,
            includeRateLimitInfoInError: Bool = true
        ) {
            self.maxRetries = maxRetries
            self.defaultRetryDelay = defaultRetryDelay
            self.maxRetryDelay = maxRetryDelay
            self.baseDelay = baseDelay
            self.backoffMultiplier = backoffMultiplier
            self.jitterFactor = jitterFactor
            self.defaultHeaders = defaultHeaders
            self.timeout = timeout
            self.includeRateLimitInfoInError = includeRateLimitInfoInError
        }

        /// Standard configuration with sensible defaults
        public static let standard = Config()

        /// Aggressive configuration for high-priority requests
        public static let aggressive = Config(
            maxRetries: 3,
            defaultRetryDelay: 30.0,
            baseDelay: 0.5,
            backoffMultiplier: 1.5,
            jitterFactor: 0.15
        )

        /// Conservative configuration for non-critical requests
        public static let conservative = Config(
            maxRetries: 10,
            defaultRetryDelay: 120.0,
            baseDelay: 2.0,
            backoffMultiplier: 3.0,
            jitterFactor: 0.2
        )
    }

    // MARK: - Errors

    /// Error types for rate-limited HTTP operations
    public enum HTTPClientError: Error, LocalizedError, Equatable {
        case invalidURL(String)
        case requestFailed(Int, Data?, RateLimitInfo?)
        case rateLimitExceeded(maxRetries: Int, lastResponse: HTTPResponse)
        case timeout
        case networkError(String)
        case tooManyRedirects

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .requestFailed(let code, _, let rateLimitInfo):
                var msg = "HTTP request failed with status \(code)"
                if let info = rateLimitInfo, let remaining = info.remaining {
                    msg += " (rate limit: \(remaining) remaining)"
                }
                return msg
            case .rateLimitExceeded(let retries, let response):
                var msg = "Rate limit exceeded after \(retries) retries"
                if let retryAfter = response.retryAfterSeconds {
                    msg += " (Retry-After: \(retryAfter)s)"
                }
                if let info = response.rateLimitInfo, let remaining = info.remaining {
                    msg += " (rate limit: \(remaining) remaining)"
                }
                return msg
            case .timeout:
                return "Request timed out"
            case .networkError(let message):
                return "Network error: \(message)"
            case .tooManyRedirects:
                return "Too many redirects"
            }
        }
    }

    // MARK: - Properties

    private let config: Config
    private let session: URLSession

    // MARK: - Initialization

    /// Create a new rate-limited HTTP client
    /// - Parameter config: Configuration for the client
    public init(config: Config = .standard) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public Methods

    /// Make an HTTP GET request with rate limit handling
    /// - Parameters:
    ///   - url: The URL to request
    ///   - headers: Additional headers for this request
    /// - Returns: HTTPResponse on success
    /// - Throws: HTTPClientError on failure
    public func get(_ url: String, headers: [String: String] = [:]) async throws -> HTTPResponse {
        return try await request(url: url, method: "GET", headers: headers)
    }

    /// Make an HTTP POST request with rate limit handling
    /// - Parameters:
    ///   - url: The URL to request
    ///   - body: Request body (Data)
    ///   - contentType: Content-Type header value
    ///   - headers: Additional headers for this request
    /// - Returns: HTTPResponse on success
    /// - Throws: HTTPClientError on failure
    public func post(
        _ url: String,
        body: Data? = nil,
        contentType: String = "application/json",
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = contentType
        return try await request(url: url, method: "POST", body: body, headers: allHeaders)
    }

    /// Make an HTTP PUT request with rate limit handling
    /// - Parameters:
    ///   - url: The URL to request
    ///   - body: Request body (Data)
    ///   - contentType: Content-Type header value
    ///   - headers: Additional headers for this request
    /// - Returns: HTTPResponse on success
    /// - Throws: HTTPClientError on failure
    public func put(
        _ url: String,
        body: Data? = nil,
        contentType: String = "application/json",
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = contentType
        return try await request(url: url, method: "PUT", body: body, headers: allHeaders)
    }

    /// Make an HTTP DELETE request with rate limit handling
    /// - Parameters:
    ///   - url: The URL to request
    ///   - headers: Additional headers for this request
    /// - Returns: HTTPResponse on success
    /// - Throws: HTTPClientError on failure
    public func delete(_ url: String, headers: [String: String] = [:]) async throws -> HTTPResponse {
        return try await request(url: url, method: "DELETE", headers: headers)
    }

    /// Make an HTTP request with automatic 429 handling and retry
    /// - Parameters:
    ///   - url: The URL to request
    ///   - method: HTTP method
    ///   - body: Request body (optional)
    ///   - headers: Additional headers
    /// - Returns: HTTPResponse on success
    /// - Throws: HTTPClientError on failure
    public func request(
        url urlString: String,
        method: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard let url = URL(string: urlString) else {
            throw HTTPClientError.invalidURL(urlString)
        }

        var lastError: Error?
        var lastResponse: HTTPResponse?

        for attempt in 0..<(config.maxRetries + 1) {
            do {
                let response = try await executeRequest(
                    url: url,
                    method: method,
                    body: body,
                    additionalHeaders: headers
                )

                if response.isSuccess {
                    return response
                }

                if response.isRateLimited && attempt < config.maxRetries {
                    lastResponse = response
                    let retryDelay = calculateRetryDelay(
                        retryAfter: response.retryAfterSeconds,
                        attempt: attempt
                    )
                    await sleep(seconds: retryDelay)
                    continue
                }

                // Non-429 error or final 429
                throw HTTPClientError.requestFailed(
                    response.statusCode,
                    response.body,
                    response.rateLimitInfo
                )
            } catch let error as HTTPClientError {
                // Don't retry HTTPClientError (already handled appropriately)
                throw error
            } catch let error as URLError {
                if error.code == .timedOut {
                    lastError = HTTPClientError.timeout
                } else {
                    lastError = HTTPClientError.networkError(error.localizedDescription)
                }
                // Retry on network errors
                if attempt < config.maxRetries {
                    let delay = calculateRetryDelay(retryAfter: nil, attempt: attempt)
                    await sleep(seconds: delay)
                    continue
                }
                if let err = lastError {
                    throw err
                } else {
                    throw HTTPClientError.networkError("Unknown error")
                }
            } catch {
                lastError = HTTPClientError.networkError(error.localizedDescription)
                if attempt < config.maxRetries {
                    let delay = calculateRetryDelay(retryAfter: nil, attempt: attempt)
                    await sleep(seconds: delay)
                    continue
                }
                if let err = lastError {
                    throw err
                } else {
                    throw HTTPClientError.networkError("Unknown error")
                }
            }
        }

        throw HTTPClientError.rateLimitExceeded(
            maxRetries: config.maxRetries,
            lastResponse: lastResponse ?? HTTPResponse(statusCode: 429, headers: [:], body: Data())
        )
    }

    // MARK: - Private Methods

    /// Execute a single HTTP request
    private func executeRequest(
        url: URL,
        method: String,
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        // Set default headers
        for (key, value) in config.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set additional headers
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Execute request
        let (data, response): (Data, URLResponse)
        if config.timeout > 0 {
            (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask {
                    try await self.session.data(for: request)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.config.timeout * 1_000_000_000))
                    throw URLError(.timedOut)
                }
                guard let result = try await group.next() else {
                    throw URLError(.timedOut)
                }
                group.cancelAll()
                return result
            }
        } else {
            (data, response) = try await session.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.networkError("Invalid response type")
        }

        // Convert headers to dictionary
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyStr = key as? String, let valueStr = value as? String {
                headers[keyStr] = valueStr
            }
        }

        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }

    /// Calculate the delay before the next retry
    private func calculateRetryDelay(retryAfter: Int?, attempt: Int) -> TimeInterval {
        // Prefer Retry-After header if present
        if let retryAfter = retryAfter {
            return min(TimeInterval(retryAfter), config.maxRetryDelay)
        }

        // Fall back to exponential backoff
        var delay = config.baseDelay * pow(config.backoffMultiplier, Double(attempt))
        delay = min(delay, config.maxRetryDelay)

        // Add jitter
        if config.jitterFactor > 0 {
            let jitter = delay * config.jitterFactor * Double.random(in: -1...1)
            delay = max(0, delay + jitter)
        }

        return delay
    }

    /// Async sleep helper
    private func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Convenience Methods

extension RateLimitedHTTPClient {

    /// Make a JSON GET request
    /// - Parameters:
    ///   - url: The URL to request
    ///   - headers: Additional headers
    /// - Returns: Decoded JSON response
    public func getJSON<T: Decodable>(_ url: String, headers: [String: String] = [:]) async throws -> T {
        let response = try await get(url, headers: headers)
        guard response.isSuccess else {
            throw HTTPClientError.requestFailed(response.statusCode, response.body, response.rateLimitInfo)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: response.body)
    }

    /// Make a JSON POST request
    /// - Parameters:
    ///   - url: The URL to request
    ///   - body: Encodable body object
    ///   - headers: Additional headers
    /// - Returns: Decoded JSON response
    public func postJSON<T: Decodable, B: Encodable>(
        _ url: String,
        body: B,
        headers: [String: String] = [:]
    ) async throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        let response = try await post(url, body: data, headers: headers)
        guard response.isSuccess else {
            throw HTTPClientError.requestFailed(response.statusCode, response.body, response.rateLimitInfo)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: response.body)
    }
}
