import XCTest
@testable import MiniMaxAgent

// MARK: - SnapshotTests
//
// These tests exercise the snapshot infrastructure introduced in Phase 9.
// Run with SNAPSHOT_RECORD_MODE=1 to write or overwrite golden files:
//
//   SNAPSHOT_RECORD_MODE=1 xcodebuild test -scheme MiniMaxAgent -testHostPath ...
//
// Omit the variable (or set it to "0") to verify against existing snapshots.

final class SnapshotTests: XCTestCase {

    // MARK: - RegistryError descriptions

    func testRegistryErrorSnapshotAlreadyRegistered() {
        let error = OrderedToolRegistry.RegistryError.toolAlreadyRegistered(id: "tool-abc")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "registry_error_already_registered")
    }

    func testRegistryErrorSnapshotNotFound() {
        let error = OrderedToolRegistry.RegistryError.toolNotFound(id: "missing-tool")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "registry_error_not_found")
    }

    func testRegistryErrorSnapshotNotFoundByName() {
        let error = OrderedToolRegistry.RegistryError.toolNotFoundByName(name: "Unknown Tool")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "registry_error_not_found_by_name")
    }

    func testRegistryErrorSnapshotCategoryNotFound() {
        let error = OrderedToolRegistry.RegistryError.categoryNotFound(category: "widgets")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "registry_error_category_not_found")
    }

    // MARK: - HTTPClientError descriptions

    func testHTTPClientErrorSnapshotInvalidURL() {
        let error = RateLimitedHTTPClient.HTTPClientError.invalidURL("not-a-url")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "http_error_invalid_url")
    }

    func testHTTPClientErrorSnapshotRequestFailed() {
        let error = RateLimitedHTTPClient.HTTPClientError.requestFailed(404, nil, nil)
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "http_error_request_failed_404")
    }

    func testHTTPClientErrorSnapshotTimeout() {
        let error = RateLimitedHTTPClient.HTTPClientError.timeout
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "http_error_timeout")
    }

    func testHTTPClientErrorSnapshotNetworkError() {
        let error = RateLimitedHTTPClient.HTTPClientError.networkError("Connection refused")
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "http_error_network_error")
    }

    func testHTTPClientErrorSnapshotTooManyRedirects() {
        let error = RateLimitedHTTPClient.HTTPClientError.tooManyRedirects
        let description = error.errorDescription ?? ""
        assertSnapshot(description, name: "http_error_too_many_redirects")
    }

    // MARK: - Config snapshots (text)

    func testHTTPConfigStandardSnapshot() {
        let config = RateLimitedHTTPClient.Config.standard
        let description = """
        maxRetries=\(config.maxRetries) \
        defaultRetryDelay=\(config.defaultRetryDelay) \
        maxRetryDelay=\(config.maxRetryDelay) \
        baseDelay=\(config.baseDelay) \
        backoffMultiplier=\(config.backoffMultiplier) \
        jitterFactor=\(config.jitterFactor) \
        timeout=\(config.timeout)
        """
        assertSnapshot(description, name: "http_config_standard")
    }

    func testHTTPConfigAggressiveSnapshot() {
        let config = RateLimitedHTTPClient.Config.aggressive
        let description = """
        maxRetries=\(config.maxRetries) \
        defaultRetryDelay=\(config.defaultRetryDelay) \
        maxRetryDelay=\(config.maxRetryDelay) \
        baseDelay=\(config.baseDelay) \
        backoffMultiplier=\(config.backoffMultiplier) \
        jitterFactor=\(config.jitterFactor) \
        timeout=\(config.timeout)
        """
        assertSnapshot(description, name: "http_config_aggressive")
    }

    func testHTTPConfigConservativeSnapshot() {
        let config = RateLimitedHTTPClient.Config.conservative
        let description = """
        maxRetries=\(config.maxRetries) \
        defaultRetryDelay=\(config.defaultRetryDelay) \
        maxRetryDelay=\(config.maxRetryDelay) \
        baseDelay=\(config.baseDelay) \
        backoffMultiplier=\(config.backoffMultiplier) \
        jitterFactor=\(config.jitterFactor) \
        timeout=\(config.timeout)
        """
        assertSnapshot(description, name: "http_config_conservative")
    }
}
