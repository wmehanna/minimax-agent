import XCTest
@testable import MiniMaxAgent

/// Tests for RateLimitedHTTPClient
final class RateLimitedHTTPClientTests: XCTestCase {

    // MARK: - HTTPResponse Tests

    func testHTTPResponseIsSuccess() {
        let response200 = RateLimitedHTTPClient.HTTPResponse(statusCode: 200, headers: [:], body: Data())
        XCTAssertTrue(response200.isSuccess)

        let response201 = RateLimitedHTTPClient.HTTPResponse(statusCode: 201, headers: [:], body: Data())
        XCTAssertTrue(response201.isSuccess)

        let response299 = RateLimitedHTTPClient.HTTPResponse(statusCode: 299, headers: [:], body: Data())
        XCTAssertTrue(response299.isSuccess)

        let response400 = RateLimitedHTTPClient.HTTPResponse(statusCode: 400, headers: [:], body: Data())
        XCTAssertFalse(response400.isSuccess)

        let response500 = RateLimitedHTTPClient.HTTPResponse(statusCode: 500, headers: [:], body: Data())
        XCTAssertFalse(response500.isSuccess)
    }

    func testHTTPResponseIsRateLimited() {
        let response429 = RateLimitedHTTPClient.HTTPResponse(statusCode: 429, headers: [:], body: Data())
        XCTAssertTrue(response429.isRateLimited)

        let response200 = RateLimitedHTTPClient.HTTPResponse(statusCode: 200, headers: [:], body: Data())
        XCTAssertFalse(response200.isRateLimited)
    }

    func testHTTPResponseBodyString() {
        let data = "Hello, World!".data(using: .utf8)!
        let response = RateLimitedHTTPClient.HTTPResponse(statusCode: 200, headers: [:], body: data)
        XCTAssertEqual(response.bodyString, "Hello, World!")
    }

    func testHTTPResponseBodyStringInvalidUTF8() {
        let data = Data([0xFF, 0xFE])
        let response = RateLimitedHTTPClient.HTTPResponse(statusCode: 200, headers: [:], body: data)
        XCTAssertNil(response.bodyString)
    }

    func testRetryAfterSecondsFromHeader() {
        let response = RateLimitedHTTPClient.HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": "30"],
            body: Data()
        )
        XCTAssertEqual(response.retryAfterSeconds, 30)
    }

    func testRetryAfterSecondsCaseInsensitive() {
        let response = RateLimitedHTTPClient.HTTPResponse(
            statusCode: 429,
            headers: ["retry-after": "60"],
            body: Data()
        )
        XCTAssertEqual(response.retryAfterSeconds, 60)
    }

    func testRateLimitInfo() {
        let response = RateLimitedHTTPClient.HTTPResponse(
            statusCode: 200,
            headers: [
                "X-RateLimit-Limit": "100",
                "X-RateLimit-Remaining": "95",
                "X-RateLimit-Reset": "1711700000"
            ],
            body: Data()
        )
        let info = response.rateLimitInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.limit, 100)
        XCTAssertEqual(info?.remaining, 95)
        XCTAssertEqual(info?.resetTimestamp, 1711700000)
    }

    // MARK: - Config Tests

    func testConfigDefaultValues() {
        let config = RateLimitedHTTPClient.Config()
        XCTAssertEqual(config.maxRetries, 5)
        XCTAssertEqual(config.defaultRetryDelay, 60.0)
        XCTAssertEqual(config.maxRetryDelay, 3600.0)
        XCTAssertEqual(config.baseDelay, 1.0)
        XCTAssertEqual(config.backoffMultiplier, 2.0)
        XCTAssertEqual(config.jitterFactor, 0.1)
        XCTAssertEqual(config.timeout, 30.0)
    }

    func testConfigStandard() {
        let config = RateLimitedHTTPClient.Config.standard
        XCTAssertEqual(config.maxRetries, 5)
        XCTAssertEqual(config.timeout, 30.0)
    }

    func testConfigAggressive() {
        let config = RateLimitedHTTPClient.Config.aggressive
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.defaultRetryDelay, 30.0)
        XCTAssertEqual(config.baseDelay, 0.5)
    }

    func testConfigConservative() {
        let config = RateLimitedHTTPClient.Config.conservative
        XCTAssertEqual(config.maxRetries, 10)
        XCTAssertEqual(config.defaultRetryDelay, 120.0)
        XCTAssertEqual(config.backoffMultiplier, 3.0)
    }

    // MARK: - Error Tests

    func testHTTPClientErrorInvalidURL() {
        let error = RateLimitedHTTPClient.HTTPClientError.invalidURL("not-a-url")
        XCTAssertEqual(error.errorDescription, "Invalid URL: not-a-url")
    }

    func testHTTPClientErrorRequestFailed() {
        let error = RateLimitedHTTPClient.HTTPClientError.requestFailed(404, nil, nil)
        XCTAssertEqual(error.errorDescription, "HTTP request failed with status 404")
    }

    func testHTTPClientErrorTimeout() {
        let error = RateLimitedHTTPClient.HTTPClientError.timeout
        XCTAssertEqual(error.errorDescription, "Request timed out")
    }

    func testHTTPClientErrorNetworkError() {
        let error = RateLimitedHTTPClient.HTTPClientError.networkError("Connection refused")
        XCTAssertEqual(error.errorDescription, "Network error: Connection refused")
    }

    func testHTTPClientErrorTooManyRedirects() {
        let error = RateLimitedHTTPClient.HTTPClientError.tooManyRedirects
        XCTAssertEqual(error.errorDescription, "Too many redirects")
    }

    // MARK: - RateLimitInfo Tests

    func testRateLimitInfoResetTime() {
        let info = RateLimitedHTTPClient.RateLimitInfo(
            limit: 100,
            remaining: 50,
            resetTimestamp: Date().timeIntervalSince1970 + 3600
        )
        XCTAssertNotNil(info.resetTime)
    }

    // MARK: - Client Initialization Tests

    func testClientInitialization() async {
        let client = RateLimitedHTTPClient()
        XCTAssertNotNil(client)
    }

    func testClientWithCustomConfig() async {
        let config = RateLimitedHTTPClient.Config(
            maxRetries: 3,
            timeout: 60.0
        )
        let client = RateLimitedHTTPClient(config: config)
        XCTAssertNotNil(client)
    }
}
