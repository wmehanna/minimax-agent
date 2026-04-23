import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - ShareItemConfiguration

/// Configures NSExtensionItem instances for use in the macOS share sheet.
///
/// Maps ``ServiceResponse/ServiceItem`` values to `NSExtensionItem` + `NSItemProvider`
/// pairs that the system share panel (`NSSharingServicePicker`) can consume.
///
/// ## Usage
/// ```swift
/// let items = response.items
/// let config = ShareItemConfiguration()
/// let extensionItems = config.extensionItems(for: items)
/// NSSharingServicePicker(items: extensionItems).show(relativeTo: .zero, of: button, preferredEdge: .minY)
/// ```
public final class ShareItemConfiguration: Sendable {

    // MARK: - Errors

    public enum ConfigurationError: Error, LocalizedError, Sendable {
        case emptyItems
        case unsupportedContentType(ServiceResponse.ContentType)
        case missingData(ServiceResponse.ContentType)

        public var errorDescription: String? {
            switch self {
            case .emptyItems:
                return "No items provided for share configuration"
            case .unsupportedContentType(let type):
                return "Content type '\(type.rawValue)' is not supported for share"
            case .missingData(let type):
                return "Required data is missing for content type '\(type.rawValue)'"
            }
        }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Converts an array of ``ServiceResponse/ServiceItem`` values into
    /// `NSExtensionItem` objects ready for the macOS share sheet.
    ///
    /// - Parameter items: The items to convert.
    /// - Returns: An array of configured `NSExtensionItem` instances.
    /// - Throws: ``ConfigurationError`` if the item list is empty or an item cannot be mapped.
    public func extensionItems(for items: [ServiceResponse.ServiceItem]) throws -> [NSExtensionItem] {
        guard !items.isEmpty else { throw ConfigurationError.emptyItems }
        return try items.map { try extensionItem(for: $0) }
    }

    /// Produces sharing-sheet–compatible objects (plain `NSItemProvider` wrappers)
    /// for use with `NSSharingServicePicker(items:)`.
    ///
    /// The sharing picker accepts `Any` — this convenience method returns the
    /// underlying provider objects directly.
    ///
    /// - Parameter items: The items to convert.
    /// - Returns: An array of objects suitable for `NSSharingServicePicker`.
    /// - Throws: ``ConfigurationError`` if the item list is empty or an item cannot be mapped.
    public func sharingItems(for items: [ServiceResponse.ServiceItem]) throws -> [Any] {
        guard !items.isEmpty else { throw ConfigurationError.emptyItems }
        return try items.compactMap { try sharingObject(for: $0) }
    }

    // MARK: - NSExtensionItem construction

    private func extensionItem(for item: ServiceResponse.ServiceItem) throws -> NSExtensionItem {
        let provider = try itemProvider(for: item)
        let extensionItem = NSExtensionItem()
        extensionItem.attachments = [provider]
        if let title = item.fileName {
            extensionItem.attributedTitle = NSAttributedString(string: title)
        }
        return extensionItem
    }

    // MARK: - NSItemProvider construction

    private func itemProvider(for item: ServiceResponse.ServiceItem) throws -> NSItemProvider {
        switch item.contentType {
        case .text:
            guard let text = item.text else {
                throw ConfigurationError.missingData(.text)
            }
            return NSItemProvider(object: text as NSString)

        case .url:
            guard let url = item.url else {
                throw ConfigurationError.missingData(.url)
            }
            return NSItemProvider(object: url as NSURL)

        case .file:
            guard let filePath = item.filePath else {
                throw ConfigurationError.missingData(.file)
            }
            let url = URL(fileURLWithPath: filePath)
            let provider = NSItemProvider()
            let typeIdentifier = uti(forMimeType: item.mimeType) ?? UTType.data
            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(url, false, nil)
                return nil
            }
            return provider

        case .image:
            guard let data = item.data, let image = NSImage(data: data) else {
                throw ConfigurationError.missingData(.image)
            }
            return NSItemProvider(object: image)

        case .directory:
            guard let dirPath = item.filePath else {
                throw ConfigurationError.missingData(.directory)
            }
            let url = URL(fileURLWithPath: dirPath, isDirectory: true)
            let provider = NSItemProvider()
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.folder.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(url, false, nil)
                return nil
            }
            return provider
        }
    }

    // MARK: - Sharing object (for NSSharingServicePicker)

    private func sharingObject(for item: ServiceResponse.ServiceItem) throws -> Any? {
        switch item.contentType {
        case .text:
            guard let text = item.text else {
                throw ConfigurationError.missingData(.text)
            }
            return text as NSString

        case .url:
            guard let url = item.url else {
                throw ConfigurationError.missingData(.url)
            }
            return url as NSURL

        case .file:
            guard let filePath = item.filePath else {
                throw ConfigurationError.missingData(.file)
            }
            return URL(fileURLWithPath: filePath) as NSURL

        case .image:
            guard let data = item.data, let image = NSImage(data: data) else {
                throw ConfigurationError.missingData(.image)
            }
            return image

        case .directory:
            guard let dirPath = item.filePath else {
                throw ConfigurationError.missingData(.directory)
            }
            return URL(fileURLWithPath: dirPath, isDirectory: true) as NSURL
        }
    }

    // MARK: - UTI helpers

    private func uti(forMimeType mimeType: String?) -> UTType? {
        guard let mimeType else { return nil }
        return UTType(mimeType: mimeType)
    }
}
