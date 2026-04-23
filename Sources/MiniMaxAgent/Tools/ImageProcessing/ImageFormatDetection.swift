import Foundation
import AppKit
import UniformTypeIdentifiers

/// Tool for detecting image formats from files, data, or NSImage instances
public actor ImageFormatDetection {

    // MARK: - Image Format Types

    /// Known image formats
    public enum ImageFormat: String, Sendable, CaseIterable {
        case jpeg = "JPEG"
        case png = "PNG"
        case heic = "HEIC"
        case gif = "GIF"
        case tiff = "TIFF"
        case bmp = "BMP"
        case webp = "WebP"
        case unknown = "Unknown"

        /// UTType corresponding to this format
        public var utType: UTType? {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .heic: return .heic
            case .gif: return .gif
            case .tiff: return .tiff
            case .bmp: return UTType("public.bmp") ?? nil
            case .webp: return UTType("public.webp") ?? nil
            case .unknown: return nil
            }
        }

        /// File extension for this format
        public var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .heic: return "heic"
            case .gif: return "gif"
            case .tiff: return "tiff"
            case .bmp: return "bmp"
            case .webp: return "webp"
            case .unknown: return "bin"
            }
        }

        /// MIME type for this format
        public var mimeType: String {
            switch self {
            case .jpeg: return "image/jpeg"
            case .png: return "image/png"
            case .heic: return "image/heic"
            case .gif: return "image/gif"
            case .tiff: return "image/tiff"
            case .bmp: return "image/bmp"
            case .webp: return "image/webp"
            case .unknown: return "application/octet-stream"
            }
        }
    }

    // MARK: - Detection Result

    /// Result of image format detection
    public struct DetectionResult: Sendable, Equatable {
        public let format: ImageFormat
        public let fileExtension: String
        public let mimeType: String
        public let width: Int?
        public let height: Int?
        public let bitDepth: Int?
        public let hasAlpha: Bool
        public let colorSpace: String?

        public init(
            format: ImageFormat,
            fileExtension: String,
            mimeType: String,
            width: Int? = nil,
            height: Int? = nil,
            bitDepth: Int? = nil,
            hasAlpha: Bool = false,
            colorSpace: String? = nil
        ) {
            self.format = format
            self.fileExtension = fileExtension
            self.mimeType = mimeType
            self.width = width
            self.height = height
            self.bitDepth = bitDepth
            self.hasAlpha = hasAlpha
            self.colorSpace = colorSpace
        }
    }

    // MARK: - Public Methods

    /// Detect format from a file path
    public func detectFormat(at path: String) async throws -> DetectionResult {
        let fileURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw ImageFormatError.fileNotFound(path)
        }

        // Get file extension
        let ext = fileURL.pathExtension.lowercased()

        // Read first bytes for magic number detection
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        guard let headerData = try fileHandle.read(upToCount: 12) else {
            throw ImageFormatError.readError
        }

        let format = detectFormatFromMagicNumber(headerData)

        // Try to get image dimensions if possible
        var width: Int?
        var height: Int?
        var bitDepth: Int?
        var hasAlpha = false
        var colorSpace: String?

        if let image = NSImage(contentsOfFile: path),
           let rep = image.representations.first {
            width = rep.pixelsWide
            height = rep.pixelsHigh
            bitDepth = rep.bitsPerSample
            hasAlpha = rep.hasAlpha
            colorSpace = rep.colorSpaceName.rawValue
        }

        return DetectionResult(
            format: format,
            fileExtension: ext,
            mimeType: format.mimeType,
            width: width,
            height: height,
            bitDepth: bitDepth,
            hasAlpha: hasAlpha,
            colorSpace: colorSpace
        )
    }

    /// Detect format from raw data
    public func detectFormat(from data: Data) async throws -> DetectionResult {
        guard data.count >= 12 else {
            throw ImageFormatError.insufficientData
        }

        let headerData = data.prefix(12)
        let format = detectFormatFromMagicNumber(Data(headerData))

        var width: Int?
        var height: Int?
        var bitDepth: Int?
        var hasAlpha = false
        var colorSpace: String?

        if let image = NSImage(data: data),
           let rep = image.representations.first {
            width = rep.pixelsWide
            height = rep.pixelsHigh
            bitDepth = rep.bitsPerSample
            hasAlpha = rep.hasAlpha
            colorSpace = rep.colorSpaceName.rawValue
        }

        return DetectionResult(
            format: format,
            fileExtension: format.fileExtension,
            mimeType: format.mimeType,
            width: width,
            height: height,
            bitDepth: bitDepth,
            hasAlpha: hasAlpha,
            colorSpace: colorSpace
        )
    }

    /// Detect format from NSImage
    public func detectFormat(from image: NSImage) async -> DetectionResult {
        // Determine format from image properties
        var detectedFormat: ImageFormat = .unknown
        var hasAlpha = false

        if let rep = image.representations.first {
            hasAlpha = rep.hasAlpha

            // Try to determine format from color space and properties
            let bitsPerSample = rep.bitsPerSample
            if bitsPerSample == 8 && hasAlpha {
                detectedFormat = .png
            } else if bitsPerSample == 8 {
                detectedFormat = .jpeg
            } else {
                detectedFormat = .png
            }
        }

        return DetectionResult(
            format: detectedFormat,
            fileExtension: detectedFormat.fileExtension,
            mimeType: detectedFormat.mimeType,
            width: image.size.width > 0 ? Int(image.size.width) : nil,
            height: image.size.height > 0 ? Int(image.size.height) : nil,
            bitDepth: nil,
            hasAlpha: hasAlpha,
            colorSpace: nil
        )
    }

    /// Check if data appears to be a supported image format
    public func isImageFormat(data: Data) async -> Bool {
        guard data.count >= 12 else { return false }
        let format = detectFormatFromMagicNumber(data)
        return format != .unknown
    }

    /// Get supported format extensions
    public func supportedExtensions() -> [String] {
        return ImageFormat.allCases
            .filter { $0 != .unknown }
            .map { $0.fileExtension }
    }

    // MARK: - Private Methods

    /// Detect format from magic number (file header bytes)
    private func detectFormatFromMagicNumber(_ data: Data) -> ImageFormat {
        guard data.count >= 12 else { return .unknown }

        let bytes = [UInt8](data)

        // JPEG: FF D8 FF
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .png
        }

        // GIF87a: 47 49 46 38 37 61
        if bytes.count >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 && bytes[4] == 0x37 && bytes[5] == 0x61 {
            return .gif
        }

        // GIF89a: 47 49 46 38 39 61
        if bytes.count >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 && bytes[4] == 0x39 && bytes[5] == 0x61 {
            return .gif
        }

        // TIFF (little endian): 49 49 2A 00
        if bytes.count >= 4 && bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00 {
            return .tiff
        }

        // TIFF (big endian): 4D 4D 00 2A
        if bytes.count >= 4 && bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A {
            return .tiff
        }

        // BMP: 42 4D
        if bytes.count >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D {
            return .bmp
        }

        // HEIC/HEIF: ftypheic, ftypmif1, ftypmif1, ftypheix, etc.
        if bytes.count >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") || brand == "heic" || brand == "heix" || brand == "mif1" || brand == "hevc" || brand == "hevx" {
                return .heic
            }
        }

        // WebP: 52 49 46 46 ... 57 45 42 50 (RIFF....WEBP)
        if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            if bytes.count >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return .webp
            }
        }

        return .unknown
    }
}

// MARK: - Errors

public enum ImageFormatError: Error, LocalizedError {
    case fileNotFound(String)
    case readError
    case insufficientData
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found at: \(path)"
        case .readError:
            return "Failed to read image file"
        case .insufficientData:
            return "Insufficient data to detect image format"
        case .unsupportedFormat:
            return "Unsupported image format"
        }
    }
}
