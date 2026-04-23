import XCTest
@testable import MiniMaxAgent

// MARK: - ExtensionContextHandlerTests
//
// Unit tests for ExtensionContextHandler.
// Uses MockExtensionContext and MockItemProvider to simulate
// the NSExtensionContext lifecycle without a live host app.

// MARK: - MockItemProvider

/// Minimal NSItemProvider subclass that returns a preset value.
private final class MockItemProvider: NSItemProvider {

    private let typeIdentifier: String
    private let returnValue: NSSecureCoding?
    private let returnError: Error?

    init(typeIdentifier: String, value: NSSecureCoding?, error: Error? = nil) {
        self.typeIdentifier = typeIdentifier
        self.returnValue = value
        self.returnError = error
        super.init()
        registerObject(ofClass: NSString.self, visibility: .all) { _ in nil }
    }

    override func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        return typeIdentifier == self.typeIdentifier
    }

    override func loadItem(
        forTypeIdentifier typeIdentifier: String,
        options: [AnyHashable: Any]?,
        completionHandler handler: NSItemProvider.CompletionHandler?
    ) {
        handler?(returnValue, returnError)
    }
}

// MARK: - MockExtensionContext

/// Lightweight NSExtensionContext subclass for testing.
private final class MockExtensionContext: NSExtensionContext {

    private let mockItems: [NSExtensionItem]
    var completeCalled = false
    var cancelCalled = false
    var cancelError: Error?

    init(items: [NSExtensionItem]) {
        self.mockItems = items
        super.init()
    }

    override var inputItems: [Any] {
        return mockItems
    }

    override func completeRequest(returningItems items: [Any]?, completionHandler: ((Bool) -> Void)? = nil) {
        completeCalled = true
        completionHandler?(true)
    }

    override func cancelRequest(withError error: Error) {
        cancelCalled = true
        cancelError = error
    }
}

// MARK: - ExtensionContextHandlerTests

final class ExtensionContextHandlerTests: XCTestCase {

    // MARK: - Properties

    var sut: ExtensionContextHandler!

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        sut = ExtensionContextHandler()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - No Input Items

    func testHandleThrowsWhenNoInputItems() async throws {
        // Arrange
        let context = MockExtensionContext(items: [])

        // Act + Assert
        do {
            _ = try await sut.handle(context: context)
            XCTFail("Expected ExtensionContextError.noInputItems to be thrown")
        } catch ExtensionContextError.noInputItems {
            // success
        }
    }

    // MARK: - No Supported Attachments

    func testHandleThrowsWhenNoSupportedAttachments() async throws {
        // Arrange: extension item with no attachments
        let item = NSExtensionItem()
        item.attachments = []
        let context = MockExtensionContext(items: [item])

        // Act + Assert
        do {
            _ = try await sut.handle(context: context)
            XCTFail("Expected ExtensionContextError.noSupportedAttachments to be thrown")
        } catch ExtensionContextError.noSupportedAttachments {
            // success
        }
    }

    // MARK: - URL Item

    func testHandleExtractsURLItem() async throws {
        // Arrange
        let url = URL(string: "https://example.com/test")!
        let provider = MockItemProvider(
            typeIdentifier: "public.url",
            value: url as NSURL
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        let context = MockExtensionContext(items: [item])

        // Act
        let response = try await sut.handle(context: context)

        // Assert
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.contentType, .url)
        XCTAssertEqual(response.items.first?.url, url)
    }

    // MARK: - Text Item

    func testHandleExtractsTextItem() async throws {
        // Arrange
        let text = "Hello from share extension"
        let provider = MockItemProvider(
            typeIdentifier: "public.plain-text",
            value: text as NSString
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        let context = MockExtensionContext(items: [item])

        // Act
        let response = try await sut.handle(context: context)

        // Assert
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.contentType, .text)
        XCTAssertEqual(response.items.first?.text, text)
    }

    // MARK: - Complete / Cancel

    func testCompleteCallsContextCompleteRequest() {
        // Arrange
        let context = MockExtensionContext(items: [])

        // Act
        sut.complete(context: context)

        // Assert
        XCTAssertTrue(context.completeCalled)
    }

    func testCancelCallsContextCancelRequest() {
        // Arrange
        let context = MockExtensionContext(items: [])

        // Act
        sut.cancel(context: context)

        // Assert
        XCTAssertTrue(context.cancelCalled)
    }

    // MARK: - Error Description

    func testErrorDescriptions() {
        XCTAssertNotNil(ExtensionContextError.noInputItems.errorDescription)
        XCTAssertNotNil(ExtensionContextError.noSupportedAttachments.errorDescription)
        XCTAssertNotNil(ExtensionContextError.unsupportedType("test.type").errorDescription)
    }
}
