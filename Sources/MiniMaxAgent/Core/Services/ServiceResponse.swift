import Foundation

/// Response format for service consumers (Share Extension, NSServices, etc.)
///
/// This struct defines the canonical format for encoding data shared from
/// MiniMaxAgent to external service consumers. It supports multiple content
/// types and provides metadata about the shared items.
///
/// ## JSON Structure
/// ```json
/// {
///   "version": "1.0",
///   "timestamp": "2026-03-29T22:05:00Z",
///   "sourceBundleId": "com.minimaxagent.app",
///   "items": [...],
///   "metadata": {...}
/// }
/// ```
public struct ServiceResponse: Sendable, Codable, Equatable {
    
    // MARK: - Types
    
    /// Supported content types in the response
    public enum ContentType: String, Sendable, Codable, CaseIterable {
        case text
        case url
        case file
        case image
        case directory
    }
    
    /// Represents a single item in the service response
    public struct ServiceItem: Sendable, Codable, Equatable, Identifiable {
        public let id: UUID
        public let contentType: ContentType
        public let data: Data?
        public let text: String?
        public let url: URL?
        public let filePath: String?
        public let fileName: String?
        public let fileSize: Int64?
        public let mimeType: String?
        
        enum CodingKeys: String, CodingKey {
            case id, contentType, data, text, url, filePath, fileName, fileSize, mimeType
        }
        
        public init(
            id: UUID = UUID(),
            contentType: ContentType,
            data: Data? = nil,
            text: String? = nil,
            url: URL? = nil,
            filePath: String? = nil,
            fileName: String? = nil,
            fileSize: Int64? = nil,
            mimeType: String? = nil
        ) {
            self.id = id
            self.contentType = contentType
            self.data = data
            self.text = text
            self.url = url
            self.filePath = filePath
            self.fileName = fileName
            self.fileSize = fileSize
            self.mimeType = mimeType
        }
        
        /// Creates a text item
        public static func text(_ text: String) -> ServiceItem {
            ServiceItem(contentType: .text, text: text)
        }
        
        /// Creates a URL item
        public static func url(_ url: URL) -> ServiceItem {
            ServiceItem(contentType: .url, url: url)
        }
        
        /// Creates a file item
        public static func file(path: String, name: String? = nil, size: Int64? = nil, mimeType: String? = nil, data: Data? = nil) -> ServiceItem {
            ServiceItem(
                contentType: .file,
                data: data,
                filePath: path,
                fileName: name ?? URL(fileURLWithPath: path).lastPathComponent,
                fileSize: size,
                mimeType: mimeType
            )
        }
        
        /// Creates an image item
        public static func image(data: Data, mimeType: String = "image/png") -> ServiceItem {
            ServiceItem(contentType: .image, data: data, mimeType: mimeType)
        }
        
        /// Creates a directory item
        public static func directory(path: String, name: String? = nil) -> ServiceItem {
            ServiceItem(
                contentType: .directory,
                filePath: path,
                fileName: name ?? URL(fileURLWithPath: path).lastPathComponent
            )
        }
    }
    
    /// Additional metadata about the response
    public struct ResponseMetadata: Sendable, Codable, Equatable {
        public let sourceAppName: String?
        public let sourceAppBundleId: String?
        public let shareMode: ShareMode?
        public let itemsCount: Int
        public let totalSize: Int64
        public let tags: [String]
        
        public enum ShareMode: String, Sendable, Codable {
            case shareExtension = "share_extension"
            case dragAndDrop = "drag_and_drop"
            case servicesMenu = "services_menu"
            case clipboard = "clipboard"
        }
        
        enum CodingKeys: String, CodingKey {
            case sourceAppName, sourceAppBundleId, shareMode, itemsCount, totalSize, tags
        }
        
        public init(
            sourceAppName: String? = nil,
            sourceAppBundleId: String? = nil,
            shareMode: ShareMode? = nil,
            itemsCount: Int,
            totalSize: Int64,
            tags: [String] = []
        ) {
            self.sourceAppName = sourceAppName
            self.sourceAppBundleId = sourceAppBundleId
            self.shareMode = shareMode
            self.itemsCount = itemsCount
            self.totalSize = totalSize
            self.tags = tags
        }
    }
    
    // MARK: - Properties
    
    /// Response format version
    public let version: String
    
    /// ISO8601 timestamp when the response was created
    public let timestamp: Date
    
    /// Bundle identifier of the source app
    public let sourceBundleId: String
    
    /// Items included in the response
    public let items: [ServiceItem]
    
    /// Response metadata
    public let metadata: ResponseMetadata
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case version, timestamp, sourceBundleId, items, metadata
    }
    
    // MARK: - Initialization
    
    public init(
        version: String = "1.0",
        timestamp: Date = Date(),
        sourceBundleId: String = "com.minimaxagent.app",
        items: [ServiceItem],
        metadata: ResponseMetadata? = nil
    ) {
        self.version = version
        self.timestamp = timestamp
        self.sourceBundleId = sourceBundleId
        self.items = items
        
        let totalSize = items.compactMap { $0.fileSize }.reduce(0, +)
        let dataSize = items.compactMap { $0.data?.count }.reduce(0, +)
        
        self.metadata = metadata ?? ResponseMetadata(
            itemsCount: items.count,
            totalSize: totalSize + Int64(dataSize)
        )
    }
    
    // MARK: - Factory Methods
    
    /// Creates a response from text content
    public static func text(_ text: String, shareMode: ResponseMetadata.ShareMode = .shareExtension) -> ServiceResponse {
        let item = ServiceItem.text(text)
        return ServiceResponse(
            items: [item],
            metadata: ResponseMetadata(
                shareMode: shareMode,
                itemsCount: 1,
                totalSize: Int64(text.utf8.count)
            )
        )
    }
    
    /// Creates a response from a URL
    public static func url(_ url: URL, shareMode: ResponseMetadata.ShareMode = .shareExtension) -> ServiceResponse {
        let item = ServiceItem.url(url)
        return ServiceResponse(
            items: [item],
            metadata: ResponseMetadata(
                shareMode: shareMode,
                itemsCount: 1,
                totalSize: 0
            )
        )
    }
    
    /// Creates a response from multiple items
    public static func multiple(_ items: [ServiceItem], shareMode: ResponseMetadata.ShareMode = .shareExtension) -> ServiceResponse {
        ServiceResponse(items: items, metadata: ResponseMetadata(shareMode: shareMode, itemsCount: items.count, totalSize: 0))
    }
    
    // MARK: - Encoding/Decoding
    
    /// Encodes the response to JSON data
    public func encode(using encoder: JSONEncoder = .iso8601) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Decodes a response from JSON data
    public static func decode(from data: Data, using decoder: JSONDecoder = .iso8601) throws -> ServiceResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ServiceResponse.self, from: data)
    }
    
    /// Converts to JSON string
    public func toJSON() throws -> String {
        let data = try encode()
        guard let string = String(data: data, encoding: .utf8) else {
            throw ServiceResponseError.encodingFailed
        }
        return string
    }
    
    /// Creates from JSON string
    public static func fromJSON(_ string: String) throws -> ServiceResponse {
        guard let data = string.data(using: .utf8) else {
            throw ServiceResponseError.decodingFailed
        }
        return try decode(from: data)
    }
}

// MARK: - Errors

public enum ServiceResponseError: Error, LocalizedError, Sendable {
    case encodingFailed
    case decodingFailed
    case invalidData
    case unsupportedContentType(String)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode service response to JSON"
        case .decodingFailed:
            return "Failed to decode service response from JSON"
        case .invalidData:
            return "Invalid data provided"
        case .unsupportedContentType(let type):
            return "Unsupported content type: \(type)"
        }
    }
}

// MARK: - ISO8601 JSON Encoder/Decoder

extension JSONEncoder {
    public static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
