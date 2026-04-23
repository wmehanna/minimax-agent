import Foundation
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Tool for encoding NSImage instances and image files to base64 strings
public actor ImageToBase64Tool {

    // MARK: - Configuration

    /// Configuration for base64 encoding
    public struct Config: Sendable {
        /// Output format for the base64 string
        public enum OutputFormat: String, Sendable {
            /// Raw base64 string
            case raw
            /// Base64 with data URI prefix (data:image/png;base64,...)
            case dataURI
            /// Base64 with MIME type prefix (data:image/jpeg;base64,...)
            case mimePrefixed
        }

        /// Compression quality for JPEG (0.0-1.0), ignored for non-JPEG
        public let compressionQuality: CGFloat

        /// Output format for the base64 string
        public let outputFormat: OutputFormat

        /// Target format for encoding (nil = preserve original)
        public let targetFormat: ImageFormatDetection.ImageFormat?

        /// Maximum dimension (width or height) for resizing before encoding
        public let maxDimension: Int?

        /// Whether to include metadata in the result
        public let includeMetadata: Bool

        public init(
            compressionQuality: CGFloat = 0.9,
            outputFormat: OutputFormat = .raw,
            targetFormat: ImageFormatDetection.ImageFormat? = nil,
            maxDimension: Int? = nil,
            includeMetadata: Bool = true
        ) {
            self.compressionQuality = compressionQuality
            self.outputFormat = outputFormat
            self.targetFormat = targetFormat
            self.maxDimension = maxDimension
            self.includeMetadata = includeMetadata
        }
    }

    // MARK: - Result Types

    /// Result of a base64 encoding operation
    public struct EncodingResult: Sendable, Equatable {
        /// Base64-encoded string
        public let base64String: String

        /// Original image dimensions
        public let width: Int

        /// Original image height
        public let height: Int

        /// Original file size in bytes (if read from file)
        public let originalFileSize: Int64?

        /// Base64-encoded size in characters
        public let base64Length: Int

        /// Image format used for encoding
        public let format: String

        /// Whether the image was resized during encoding
        public let wasResized: Bool

        /// Original dimensions if resized
        public let originalWidth: Int?

        /// Original height if resized
        public let originalHeight: Int?

        /// MIME type of the encoded image
        public let mimeType: String

        /// Human-readable summary
        public var summary: String {
            var parts = ["\(width)×\(height)", format]
            if wasResized, let ow = originalWidth, let oh = originalHeight {
                parts.insert("resized from \(ow)×\(oh)", at: 0)
            }
            parts.append("(\(ByteCountFormatter.string(fromByteCount: Int64(base64Length * 3 / 4), countStyle: .file)))")
            return parts.joined(separator: ", ")
        }

        public init(
            base64String: String,
            width: Int,
            height: Int,
            originalFileSize: Int64? = nil,
            format: String,
            wasResized: Bool = false,
            originalWidth: Int? = nil,
            originalHeight: Int? = nil,
            mimeType: String
        ) {
            self.base64String = base64String
            self.width = width
            self.height = height
            self.originalFileSize = originalFileSize
            self.base64Length = base64String.count
            self.format = format
            self.wasResized = wasResized
            self.originalWidth = originalWidth
            self.originalHeight = originalHeight
            self.mimeType = mimeType
        }
    }

    // MARK: - Properties

    private let config: Config
    private let formatDetection: ImageFormatDetection

    // MARK: - Initialization

    public init(config: Config = Config()) {
        self.config = config
        self.formatDetection = ImageFormatDetection()
    }

    // MARK: - Public Methods

    /// Encode an image file to base64
    /// - Parameter path: File path to the image
    /// - Returns: EncodingResult containing the base64 string and metadata
    public func encodeImage(at path: String) async throws -> EncodingResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ImageToBase64Error.fileNotFound(path)
        }

        // Get original file size
        let originalFileSize: Int64? = {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return attributes?[.size] as? Int64
        }()

        // Detect original format
        let detectionResult = try await formatDetection.detectFormat(at: path)
        let originalWidth = Int(detectionResult.width ?? 0)
        let originalHeight = Int(detectionResult.height ?? 0)

        // Load image
        guard let image = NSImage(contentsOfFile: path) else {
            throw ImageToBase64Error.invalidImageFile(path)
        }

        // Resize if needed
        let (processedImage, resized) = try await processImage(
            image,
            targetWidth: originalWidth,
            targetHeight: originalHeight
        )

        // Encode to base64
        return try await encodeNSImage(
            processedImage,
            targetFormat: config.targetFormat ?? detectionResult.format,
            originalWidth: resized ? originalWidth : nil,
            originalHeight: resized ? originalHeight : nil,
            originalFileSize: originalFileSize
        )
    }

    /// Encode an NSImage to base64
    /// - Parameters:
    ///   - image: The NSImage to encode
    ///   - targetFormat: Optional format override
    /// - Returns: EncodingResult containing the base64 string and metadata
    public func encodeImage(_ image: NSImage, targetFormat: ImageFormatDetection.ImageFormat? = nil) async throws -> EncodingResult {
        let originalWidth = Int(image.size.width)
        let originalHeight = Int(image.size.height)

        // Resize if needed
        let (processedImage, resized) = try await processImage(
            image,
            targetWidth: originalWidth,
            targetHeight: originalHeight
        )

        return try await encodeNSImage(
            processedImage,
            targetFormat: targetFormat ?? .png,
            originalWidth: resized ? originalWidth : nil,
            originalHeight: resized ? originalHeight : nil,
            originalFileSize: nil
        )
    }

    /// Encode image data directly to base64
    /// - Parameter data: Raw image data
    /// - Returns: EncodingResult containing the base64 string and metadata
    public func encodeImageData(_ data: Data) async throws -> EncodingResult {
        guard let image = NSImage(data: data) else {
            throw ImageToBase64Error.invalidImageData
        }

        // Try to detect format
        let detectionResult = try await formatDetection.detectFormat(from: data)
        let originalWidth = Int(detectionResult.width ?? 0)
        let originalHeight = Int(detectionResult.height ?? 0)

        // Resize if needed
        let (processedImage, resized) = try await processImage(
            image,
            targetWidth: originalWidth,
            targetHeight: originalHeight
        )

        return try await encodeNSImage(
            processedImage,
            targetFormat: config.targetFormat ?? detectionResult.format,
            originalWidth: resized ? originalWidth : nil,
            originalHeight: resized ? originalHeight : nil,
            originalFileSize: Int64(data.count)
        )
    }

    // MARK: - Private Methods

    /// Process (resize) image if needed based on config
    private func processImage(_ image: NSImage, targetWidth: Int, targetHeight: Int) async throws -> (NSImage, Bool) {
        guard let maxDim = config.maxDimension, maxDim > 0 else {
            return (image, false)
        }

        let maxOfDim = max(targetWidth, targetHeight)
        guard maxOfDim > maxDim else {
            return (image, false)
        }

        // Calculate scaled dimensions maintaining aspect ratio
        let scale = CGFloat(maxDim) / CGFloat(maxOfDim)
        let newWidth = Int(CGFloat(targetWidth) * scale)
        let newHeight = Int(CGFloat(targetHeight) * scale)

        return (try resizeImage(image, to: NSSize(width: newWidth, height: newHeight)), true)
    }

    /// Resize NSImage to target size
    private func resizeImage(_ image: NSImage, to targetSize: NSSize) throws -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    /// Core encoding logic for NSImage -> base64
    private func encodeNSImage(
        _ image: NSImage,
        targetFormat: ImageFormatDetection.ImageFormat,
        originalWidth: Int?,
        originalHeight: Int?,
        originalFileSize: Int64?
    ) async throws -> EncodingResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageToBase64Error.cgImageConversionFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let format = targetFormat

        // Convert to appropriate format and get data
        let imageData: Data?
        let mimeType: String

        switch format {
        case .jpeg:
            mimeType = "image/jpeg"
            imageData = createJPEGData(from: cgImage, quality: config.compressionQuality)
        case .png:
            mimeType = "image/png"
            imageData = createPNGData(from: cgImage)
        case .heic:
            mimeType = "image/heic"
            imageData = createHEICData(from: cgImage)
        case .gif:
            mimeType = "image/gif"
            imageData = createGIFData(from: cgImage)
        case .tiff:
            mimeType = "image/tiff"
            imageData = createTIFFData(from: cgImage)
        case .webp:
            mimeType = "image/webp"
            imageData = createWebPData(from: cgImage)
        default:
            mimeType = "image/png"
            imageData = createPNGData(from: cgImage)
        }

        guard let data = imageData else {
            throw ImageToBase64Error.encodingFailed(format.rawValue)
        }

        let base64String: String
        switch config.outputFormat {
        case .raw:
            base64String = data.base64EncodedString()
        case .dataURI:
            base64String = "data:\(mimeType);base64,\(data.base64EncodedString())"
        case .mimePrefixed:
            base64String = "data:\(mimeType);base64,\(data.base64EncodedString())"
        }

        return EncodingResult(
            base64String: base64String,
            width: width,
            height: height,
            originalFileSize: originalFileSize,
            format: format.rawValue,
            wasResized: originalWidth != nil,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            mimeType: mimeType
        )
    }

    /// Create JPEG data from CGImage
    private func createJPEGData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Create PNG data from CGImage
    private func createPNGData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Create HEIC data from CGImage using CGImageDestination
    private func createHEICData(from cgImage: CGImage) -> Data? {
        guard let heicUTType = UTType("public.heic") else {
            return createPNGData(from: cgImage)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, heicUTType.identifier as CFString, 1, nil) else {
            return createPNGData(from: cgImage)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return createPNGData(from: cgImage)
        }
        return data as Data
    }

    /// Create GIF data from CGImage
    private func createGIFData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .gif, properties: [:])
    }

    /// Create TIFF data from CGImage
    private func createTIFFData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .tiff, properties: [:])
    }

    /// Create WebP data from CGImage
    private func createWebPData(from cgImage: CGImage) -> Data? {
        // WebP encoding not natively supported via AppKit; fall back to PNG
        return createPNGData(from: cgImage)
    }
}

// MARK: - Errors

public enum ImageToBase64Error: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case invalidImageFile(String)
    case invalidImageData
    case cgImageConversionFailed
    case encodingFailed(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found at: \(path)"
        case .invalidImageFile(let path):
            return "Could not load image from file: \(path)"
        case .invalidImageData:
            return "Could not load image from provided data"
        case .cgImageConversionFailed:
            return "Failed to convert NSImage to CGImage"
        case .encodingFailed(let format):
            return "Failed to encode image to format: \(format)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        }
    }
}
