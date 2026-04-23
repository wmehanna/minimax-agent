import Foundation
import UniformTypeIdentifiers

// MARK: - ExtensionContextHandler
//
// Handles NSExtensionContext lifecycle for the Share Extension target.
// Responsible for extracting NSExtensionItem attachments, loading item
// providers, and completing or cancelling the extension request.
//
// ## Overview
//
// When the host app invokes the Share Extension, the system provides an
// `NSExtensionContext` containing one or more `NSExtensionItem` objects.
// Each item may carry multiple `NSItemProvider` attachments representing
// different representations of the shared data (URL, text, file data…).
//
// This handler:
// 1. Receives the context from the view controller.
// 2. Extracts all `NSExtensionItem` attachments.
// 3. Loads each provider asynchronously.
// 4. Converts loaded data into `ServiceResponse` values.
// 5. Calls `completeRequest` or `cancelRequest` on the context.
//
// ## Usage
//
// ```swift
// let handler = ExtensionContextHandler()
// let response = try await handler.handle(context: extensionContext!)
// ```

// MARK: - ExtensionContextError

/// Errors thrown by `ExtensionContextHandler`.
public enum ExtensionContextError: Error, LocalizedError, Sendable {
    case noInputItems
    case noSupportedAttachments
    case loadFailed(Error)
    case unsupportedType(String)

    public var errorDescription: String? {
        switch self {
        case .noInputItems:
            return "The extension context contains no input items."
        case .noSupportedAttachments:
            return "None of the attachments are of a supported type."
        case .loadFailed(let underlying):
            return "Failed to load attachment: \(underlying.localizedDescription)"
        case .unsupportedType(let identifier):
            return "Unsupported type identifier: \(identifier)"
        }
    }
}

// MARK: - ExtensionContextHandler

/// Handles an `NSExtensionContext` by extracting shared items and
/// converting them to a `ServiceResponse`.
public final class ExtensionContextHandler: Sendable {

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public API

    /// Processes all input items in the given extension context.
    ///
    /// - Parameter context: The `NSExtensionContext` provided by the system.
    /// - Returns: A `ServiceResponse` aggregating all loaded items.
    /// - Throws: `ExtensionContextError` if no usable items can be extracted.
    public func handle(context: NSExtensionContext) async throws -> ServiceResponse {
        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
        guard !items.isEmpty else {
            throw ExtensionContextError.noInputItems
        }

        var serviceItems: [ServiceResponse.ServiceItem] = []

        for extensionItem in items {
            let attachments = extensionItem.attachments ?? []
            for provider in attachments {
                if let item = try await loadItem(from: provider) {
                    serviceItems.append(item)
                }
            }
        }

        guard !serviceItems.isEmpty else {
            throw ExtensionContextError.noSupportedAttachments
        }

        if serviceItems.count == 1, let single = serviceItems.first {
            return makeSingleItemResponse(single)
        }
        return .multiple(serviceItems, shareMode: .shareExtension)
    }

    /// Completes the extension request with optional return items.
    ///
    /// - Parameters:
    ///   - context: The active `NSExtensionContext`.
    ///   - returningItems: Items to return to the host app (may be nil).
    public func complete(context: NSExtensionContext, returningItems: [Any]? = nil) {
        context.completeRequest(returningItems: returningItems ?? [])
    }

    /// Cancels the extension request with an optional error.
    ///
    /// - Parameters:
    ///   - context: The active `NSExtensionContext`.
    ///   - error: The reason for cancellation (optional).
    public func cancel(context: NSExtensionContext, withError error: Error? = nil) {
        context.cancelRequest(withError: error ?? ExtensionContextError.noSupportedAttachments)
    }

    // MARK: - Private Helpers

    /// Loads a single `ServiceResponse.ServiceItem` from an `NSItemProvider`.
    /// Returns `nil` when the provider's type is not supported.
    private func loadItem(from provider: NSItemProvider) async throws -> ServiceResponse.ServiceItem? {
        // Priority: URL → plain text → file data
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await loadURL(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadText(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await loadFile(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return try await loadData(from: provider)
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async throws -> ServiceResponse.ServiceItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.url.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: ExtensionContextError.loadFailed(error))
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: .url(url))
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: .url(url))
                } else {
                    continuation.resume(throwing: ExtensionContextError.unsupportedType(UTType.url.identifier))
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async throws -> ServiceResponse.ServiceItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.plainText.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: ExtensionContextError.loadFailed(error))
                    return
                }
                if let text = item as? String {
                    continuation.resume(returning: .text(text))
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: .text(text))
                } else {
                    continuation.resume(throwing: ExtensionContextError.unsupportedType(UTType.plainText.identifier))
                }
            }
        }
    }

    private func loadFile(from provider: NSItemProvider) async throws -> ServiceResponse.ServiceItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: ExtensionContextError.loadFailed(error))
                    return
                }
                if let url = item as? URL {
                    let name = url.lastPathComponent
                    continuation.resume(returning: .file(path: url.path, name: name))
                } else {
                    continuation.resume(throwing: ExtensionContextError.unsupportedType(UTType.fileURL.identifier))
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider) async throws -> ServiceResponse.ServiceItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.data.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: ExtensionContextError.loadFailed(error))
                    return
                }
                if let data = item as? Data {
                    let serviceItem = ServiceResponse.ServiceItem(
                        contentType: .file,
                        data: data
                    )
                    continuation.resume(returning: serviceItem)
                } else {
                    continuation.resume(throwing: ExtensionContextError.unsupportedType(UTType.data.identifier))
                }
            }
        }
    }

    private func makeSingleItemResponse(_ item: ServiceResponse.ServiceItem) -> ServiceResponse {
        switch item.contentType {
        case .text:
            return .text(item.text ?? "", shareMode: .shareExtension)
        case .url:
            if let url = item.url {
                return .url(url, shareMode: .shareExtension)
            }
            return .multiple([item], shareMode: .shareExtension)
        default:
            return .multiple([item], shareMode: .shareExtension)
        }
    }
}
