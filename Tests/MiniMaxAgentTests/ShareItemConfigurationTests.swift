import XCTest
@testable import MiniMaxAgent

final class ShareItemConfigurationTests: XCTestCase {

    private var sut: ShareItemConfiguration!

    override func setUp() {
        super.setUp()
        sut = ShareItemConfiguration()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - extensionItems(for:)

    func testExtensionItemsThrowsForEmptyArray() throws {
        XCTAssertThrowsError(try sut.extensionItems(for: [])) { error in
            guard case ShareItemConfiguration.ConfigurationError.emptyItems = error else {
                XCTFail("Expected .emptyItems, got \(error)")
                return
            }
        }
    }

    func testExtensionItemsForSingleTextItem() throws {
        let item = ServiceResponse.ServiceItem.text("Hello, share sheet")
        let result = try sut.extensionItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].attachments?.count, 1)
    }

    func testExtensionItemsForURLItem() throws {
        let url = URL(string: "https://example.com")!
        let item = ServiceResponse.ServiceItem.url(url)
        let result = try sut.extensionItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].attachments?.count, 1)
    }

    func testExtensionItemsForImageItem() throws {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        guard let tiff = image.tiffRepresentation else {
            XCTFail("Could not produce TIFF data from NSImage")
            return
        }
        let item = ServiceResponse.ServiceItem.image(data: tiff, mimeType: "image/tiff")
        let result = try sut.extensionItems(for: [item])

        XCTAssertEqual(result.count, 1)
    }

    func testExtensionItemsForFileItem() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-share-\(UUID().uuidString).txt")
        try "content".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = ServiceResponse.ServiceItem.file(
            path: tmp.path,
            name: tmp.lastPathComponent,
            mimeType: "text/plain"
        )
        let result = try sut.extensionItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].attributedTitle?.string, tmp.lastPathComponent)
    }

    func testExtensionItemsForDirectoryItem() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = ServiceResponse.ServiceItem.directory(path: tmp.path, name: "MyFolder")
        let result = try sut.extensionItems(for: [item])

        XCTAssertEqual(result.count, 1)
    }

    func testExtensionItemsForMultipleItems() throws {
        let items: [ServiceResponse.ServiceItem] = [
            .text("Alpha"),
            .url(URL(string: "https://beta.com")!),
            .text("Gamma"),
        ]
        let result = try sut.extensionItems(for: items)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - sharingItems(for:)

    func testSharingItemsThrowsForEmptyArray() throws {
        XCTAssertThrowsError(try sut.sharingItems(for: [])) { error in
            guard case ShareItemConfiguration.ConfigurationError.emptyItems = error else {
                XCTFail("Expected .emptyItems, got \(error)")
                return
            }
        }
    }

    func testSharingItemsReturnsNSStringForText() throws {
        let item = ServiceResponse.ServiceItem.text("share me")
        let result = try sut.sharingItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0] is NSString)
    }

    func testSharingItemsReturnsNSURLForURL() throws {
        let url = URL(string: "https://example.org")!
        let item = ServiceResponse.ServiceItem.url(url)
        let result = try sut.sharingItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0] is NSURL)
    }

    func testSharingItemsReturnsNSImageForImage() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        guard let tiff = image.tiffRepresentation else {
            XCTFail("No TIFF data")
            return
        }
        let item = ServiceResponse.ServiceItem.image(data: tiff)
        let result = try sut.sharingItems(for: [item])

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0] is NSImage)
    }

    // MARK: - Missing data errors

    func testExtensionItemTextWithNoTextThrows() throws {
        let item = ServiceResponse.ServiceItem(contentType: .text, text: nil)
        XCTAssertThrowsError(try sut.extensionItems(for: [item])) { error in
            guard case ShareItemConfiguration.ConfigurationError.missingData(let type) = error else {
                XCTFail("Expected .missingData, got \(error)")
                return
            }
            XCTAssertEqual(type, .text)
        }
    }

    func testExtensionItemURLWithNoURLThrows() throws {
        let item = ServiceResponse.ServiceItem(contentType: .url, url: nil)
        XCTAssertThrowsError(try sut.extensionItems(for: [item])) { error in
            guard case ShareItemConfiguration.ConfigurationError.missingData(let type) = error else {
                XCTFail("Expected .missingData, got \(error)")
                return
            }
            XCTAssertEqual(type, .url)
        }
    }

    func testExtensionItemImageWithNoDataThrows() throws {
        let item = ServiceResponse.ServiceItem(contentType: .image, data: nil)
        XCTAssertThrowsError(try sut.extensionItems(for: [item])) { error in
            guard case ShareItemConfiguration.ConfigurationError.missingData(let type) = error else {
                XCTFail("Expected .missingData, got \(error)")
                return
            }
            XCTAssertEqual(type, .image)
        }
    }
}
