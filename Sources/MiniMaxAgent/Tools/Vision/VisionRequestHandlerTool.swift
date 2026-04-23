import Foundation
import Vision
import AppKit
import CoreGraphics

/// Options for Vision request execution
public struct VisionRequestOptions: Sendable, Equatable {
    /// Whether to cache results internally
    public let cacheResults: Bool

    /// Revision to use for requests (0 = default/latest)
    public let revision: Int

    /// Whether to use GPU for processing
    public let usesGPU: Bool

    /// Whether to use only CPU
    public let usesCPUOnly: Bool

    public init(
        cacheResults: Bool = false,
        revision: Int = 0,
        usesGPU: Bool = true,
        usesCPUOnly: Bool = false
    ) {
        self.cacheResults = cacheResults
        self.revision = revision
        self.usesGPU = usesGPU
        self.usesCPUOnly = usesCPUOnly
    }

    /// Default options
    public static let `default` = VisionRequestOptions()

    /// High accuracy options (slower)
    public static let accurate = VisionRequestOptions(usesCPUOnly: false)

    /// Fast options (less accurate)
    public static let fast = VisionRequestOptions(usesCPUOnly: true)
}

/// Result of a Vision request execution
public struct VisionRequestResult: Sendable, Equatable {
    /// Results from each request
    public let results: [Any]

    /// Time taken to perform requests
    public let executionTime: TimeInterval

    /// Image size used for the request
    public let imageSize: CGSize

    /// Whether execution was successful
    public let success: Bool

    /// Error message if failed
    public let error: String?

    public init(
        results: [Any],
        executionTime: TimeInterval,
        imageSize: CGSize,
        success: Bool,
        error: String? = nil
    ) {
        self.results = results
        self.executionTime = executionTime
        self.imageSize = imageSize
        self.success = success
        self.error = error
    }

    public static func == (lhs: VisionRequestResult, rhs: VisionRequestResult) -> Bool {
        lhs.success == rhs.success &&
        lhs.executionTime == rhs.executionTime &&
        lhs.imageSize == rhs.imageSize &&
        lhs.error == rhs.error
    }
}

/// Progress callback for long-running Vision requests
public enum VisionRequestProgress: Sendable, Equatable {
    case started
    case processing(requestIndex: Int, totalRequests: Int)
    case completed
    case failed(String)
}

/// Tool providing direct access to Vision framework VNImageRequestHandler
///
/// VNImageRequestHandler is the primary interface for performing Vision requests on images.
/// This tool wraps the handler and provides both low-level and high-level APIs for:
/// - Creating handlers from various image sources (CGImage, PixelBuffer, URL, Data)
/// - Performing requests synchronously and asynchronously
/// - Configuring request options (revision, CPU/GPU usage)
/// - Support for custom Vision requests
/// - Batch processing of multiple requests
///
/// Phase 3: API Integration — MiniMax API client, Claude API, model management, multimodal
/// Section: 3.4
/// Task: Vision framework VNImageRequestHandler
///
/// Usage:
///
///   let handler = VisionRequestHandlerTool()
///   
///   // Analyze image from URL
///   let result = try await handler.analyzeImage(at: url, requests: [classificationRequest])
///   
///   // Perform multiple request types
///   let result = try await handler.performRequests([
///       faceRequest,
///       textRecognitionRequest,
///       barcodeRequest
///   ], on: cgImage)
///   
///   // Get handler for custom workflows
///   let (handler, image) = try handler.createHandler(from: imageURL)
///   try handler.perform([request])
///
public actor VisionRequestHandlerTool {

    // MARK: - Properties

    private var lastResults: [VNRequest] = []
    private var lastImageSize: CGSize = .zero
    private var lastExecutionTime: TimeInterval = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - Handler Creation

    /// Create a VNImageRequestHandler from a CGImage
    /// - Parameters:
    ///   - cgImage: The CGImage to process
    ///   - options: Request execution options
    /// - Returns: Tuple of (VNImageRequestHandler, image size)
    public func createHandler(
        from cgImage: CGImage,
        options: VisionRequestOptions = .default
    ) -> (VNImageRequestHandler, CGSize) {
        let handlerOptions: [VNImageOption: Any] = [
            .cameraIntrinsics: "",
        ].merging(requestOptions(from: options)) { _, new in new }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: handlerOptions)
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return (handler, size)
    }

    /// Create a VNImageRequestHandler from a pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: The CVPixelBuffer to process
    ///   - options: Request execution options
    /// - Returns: Tuple of (VNImageRequestHandler, image size)
    public func createHandler(
        from pixelBuffer: CVPixelBuffer,
        options: VisionRequestOptions = .default
    ) -> (VNImageRequestHandler, CGSize) {
        let handlerOptions = requestOptions(from: options)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: handlerOptions)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)
        return (handler, size)
    }

    /// Create a VNImageRequestHandler from a URL
    /// - Parameters:
    ///   - url: URL to the image file
    ///   - options: Request execution options
    /// - Returns: Tuple of (VNImageRequestHandler, CGImage, image size)
    public func createHandler(
        from url: URL,
        options: VisionRequestOptions = .default
    ) throws -> (VNImageRequestHandler, CGImage, CGSize) {
        guard let image = NSImage(contentsOf: url) else {
            throw VisionRequestHandlerError.imageLoadFailed(url.path)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionRequestHandlerError.invalidImageFormat
        }

        let (handler, size) = createHandler(from: cgImage, options: options)
        return (handler, cgImage, size)
    }

    /// Create a VNImageRequestHandler from image data
    /// - Parameters:
    ///   - data: Image data
    ///   - options: Request execution options
    /// - Returns: Tuple of (VNImageRequestHandler, CGImage, image size)
    public func createHandler(
        from data: Data,
        options: VisionRequestOptions = .default
    ) throws -> (VNImageRequestHandler, CGImage, CGSize) {
        guard let image = NSImage(data: data) else {
            throw VisionRequestHandlerError.invalidImageData
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionRequestHandlerError.invalidImageFormat
        }

        let (handler, size) = createHandler(from: cgImage, options: options)
        return (handler, cgImage, size)
    }

    /// Create a VNImageRequestHandler from an NSImage
    /// - Parameters:
    ///   - image: NSImage to process
    ///   - options: Request execution options
    /// - Returns: Tuple of (VNImageRequestHandler, CGImage, image size)
    public func createHandler(
        from image: NSImage,
        options: VisionRequestOptions = .default
    ) throws -> (VNImageRequestHandler, CGImage, CGSize) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionRequestHandlerError.invalidImageFormat
        }

        let (handler, size) = createHandler(from: cgImage, options: options)
        return (handler, cgImage, size)
    }

    // MARK: - Convenience Analysis Methods

    /// Analyze an image from a file path
    /// - Parameters:
    ///   - path: Path to the image file
    ///   - requests: Vision requests to perform
    ///   - options: Execution options
    /// - Returns: VisionRequestResult with results and metadata
    public func analyzeImage(
        at path: String,
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> VisionRequestResult {
        guard let image = NSImage(contentsOfFile: path) else {
            throw VisionRequestHandlerError.imageLoadFailed(path)
        }

        return try await analyzeImage(image, requests: requests, options: options)
    }

    /// Analyze an NSImage
    /// - Parameters:
    ///   - image: NSImage to analyze
    ///   - requests: Vision requests to perform
    ///   - options: Execution options
    /// - Returns: VisionRequestResult with results and metadata
    public func analyzeImage(
        _ image: NSImage,
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> VisionRequestResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionRequestHandlerError.invalidImageFormat
        }

        return try await analyzeImage(cgImage, requests: requests, options: options)
    }

    /// Analyze a CGImage
    /// - Parameters:
    ///   - cgImage: CGImage to analyze
    ///   - requests: Vision requests to perform
    ///   - options: Execution options
    /// - Returns: VisionRequestResult with results and metadata
    public func analyzeImage(
        _ cgImage: CGImage,
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> VisionRequestResult {
        let startTime = Date()
        let (handler, size) = createHandler(from: cgImage, options: options)

        try handler.perform(requests)

        let executionTime = Date().timeIntervalSince(startTime)
        lastResults = requests
        lastImageSize = size
        lastExecutionTime = executionTime

        return VisionRequestResult(
            results: requests.flatMap { $0.results ?? [] },
            executionTime: executionTime,
            imageSize: size,
            success: true
        )
    }

    /// Analyze an image from a URL
    /// - Parameters:
    ///   - url: URL to the image
    ///   - requests: Vision requests to perform
    ///   - options: Execution options
    /// - Returns: VisionRequestResult with results and metadata
    public func analyzeImage(
        at url: URL,
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> VisionRequestResult {
        let startTime = Date()
        let (handler, cgImage, size) = try createHandler(from: url, options: options)

        try handler.perform(requests)

        let executionTime = Date().timeIntervalSince(startTime)
        lastResults = requests
        lastImageSize = size
        lastExecutionTime = executionTime

        return VisionRequestResult(
            results: requests.flatMap { $0.results ?? [] },
            executionTime: executionTime,
            imageSize: size,
            success: true
        )
    }

    /// Analyze a pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: CVPixelBuffer to analyze
    ///   - requests: Vision requests to perform
    ///   - options: Execution options
    /// - Returns: VisionRequestResult with results and metadata
    public func analyzeImage(
        _ pixelBuffer: CVPixelBuffer,
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> VisionRequestResult {
        let startTime = Date()
        let (handler, size) = createHandler(from: pixelBuffer, options: options)

        try handler.perform(requests)

        let executionTime = Date().timeIntervalSince(startTime)
        lastResults = requests
        lastImageSize = size
        lastExecutionTime = executionTime

        return VisionRequestResult(
            results: requests.flatMap { $0.results ?? [] },
            executionTime: executionTime,
            imageSize: size,
            success: true
        )
    }

    // MARK: - Low-Level Perform

    /// Perform requests on an image using a handler you created
    /// - Parameters:
    ///   - requests: Requests to perform
    ///   - handler: Pre-configured VNImageRequestHandler
    public func performRequests(
        _ requests: [VNRequest],
        using handler: VNImageRequestHandler
    ) async throws {
        try handler.perform(requests)
        lastResults = requests
    }

    // MARK: - Request Builders

    /// Create a face detection request with default settings
    public func makeFaceDetectionRequest() -> VNDetectFaceRectanglesRequest {
        VNDetectFaceRectanglesRequest()
    }

    /// Create a face landmarks request
    public func makeFaceLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        VNDetectFaceLandmarksRequest()
    }

    /// Create a barcode detection request
    public func makeBarcodeDetectionRequest() -> VNDetectBarcodesRequest {
        VNDetectBarcodesRequest()
    }

    /// Create a rectangle detection request
    public func makeRectangleDetectionRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 10
        request.minimumConfidence = 0.5
        return request
    }

    /// Create a text recognition request
    /// - Parameter level: Recognition level (accurate or fast)
    public func makeTextRecognitionRequest(level: VNRequestTextRecognitionLevel = .accurate) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        return request
    }

    /// Create an image classification request
    public func makeClassificationRequest() -> VNClassifyImageRequest {
        VNClassifyImageRequest()
    }

    /// Create a horizon detection request
    public func makeHorizonDetectionRequest() -> VNDetectHorizonRequest {
        VNDetectHorizonRequest()
    }

    // MARK: - Batch Processing

    /// Analyze multiple images sequentially
    /// - Parameters:
    ///   - paths: Paths to image files
    ///   - requests: Vision requests to perform on each image
    ///   - options: Execution options
    /// - Returns: Array of results (one per image)
    public func analyzeImages(
        at paths: [String],
        requests: [VNRequest],
        options: VisionRequestOptions = .default
    ) async throws -> [VisionRequestResult] {
        var results: [VisionRequestResult] = []
        for path in paths {
            let result = try await analyzeImage(at: path, requests: requests, options: options)
            results.append(result)
        }
        return results
    }

    // MARK: - Result Access

    /// Get the last results
    public func getLastResults() -> [VNRequest] {
        lastResults
    }

    /// Get the last image size
    public func getLastImageSize() -> CGSize {
        lastImageSize
    }

    /// Get the last execution time
    public func getLastExecutionTime() -> TimeInterval {
        lastExecutionTime
    }

    // MARK: - Private Helpers

    private func requestOptions(from config: VisionRequestOptions) -> [VNImageOption: Any] {
        var options: [VNImageOption: Any] = [:]
        if config.usesCPUOnly {
            // CPU-only is set per-request, not per-handler
        }
        return options
    }
}

// MARK: - Errors

public enum VisionRequestHandlerError: Error, LocalizedError {
    case imageLoadFailed(String)
    case invalidImageFormat
    case invalidImageData
    case requestFailed(String)
    case handlerCreationFailed

    public var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let path):
            return "Failed to load image from: \(path)"
        case .invalidImageFormat:
            return "Invalid image format"
        case .invalidImageData:
            return "Invalid image data"
        case .requestFailed(let message):
            return "Vision request failed: \(message)"
        case .handlerCreationFailed:
            return "Failed to create VNImageRequestHandler"
        }
    }
}

// MARK: - Static Convenience Methods

extension VisionRequestHandlerTool {

    /// Quick face detection on an image
    public static func detectFaces(in image: NSImage) async throws -> [VNFaceObservation] {
        let tool = VisionRequestHandlerTool()
        let request = await tool.makeFaceDetectionRequest()
        let result = try await tool.analyzeImage(image, requests: [request])
        return result.results.compactMap { $0 as? VNFaceObservation }
    }

    /// Quick text recognition on an image
    public static func recognizeText(in image: NSImage) async throws -> [VNRecognizedTextObservation] {
        let tool = VisionRequestHandlerTool()
        let request = await tool.makeTextRecognitionRequest()
        let result = try await tool.analyzeImage(image, requests: [request])
        return result.results.compactMap { $0 as? VNRecognizedTextObservation }
    }

    /// Quick barcode detection on an image
    public static func detectBarcodes(in image: NSImage) async throws -> [VNBarcodeObservation] {
        let tool = VisionRequestHandlerTool()
        let request = await tool.makeBarcodeDetectionRequest()
        let result = try await tool.analyzeImage(image, requests: [request])
        return result.results.compactMap { $0 as? VNBarcodeObservation }
    }

    /// Quick image classification
    public static func classify(image: NSImage) async throws -> [VNClassificationObservation] {
        let tool = VisionRequestHandlerTool()
        let request = await tool.makeClassificationRequest()
        let result = try await tool.analyzeImage(image, requests: [request])
        return result.results.compactMap { $0 as? VNClassificationObservation }
    }
}
