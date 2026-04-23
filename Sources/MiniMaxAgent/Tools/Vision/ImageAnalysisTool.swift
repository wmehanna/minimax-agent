import Foundation
import Vision
import AppKit

/// Unified tool for image analysis using Vision framework
/// Combines image capture, request execution, and response handling
public actor ImageAnalysisTool {

    // MARK: - Analysis Types

    public enum AnalysisType: String, CaseIterable, Sendable {
        case classification
        case faceDetection
        case textRecognition
        case barcodeDetection
        case rectangleDetection
        case all

        public var requestType: VNRequest {
            switch self {
            case .classification:
                return VNClassifyImageRequest()
            case .faceDetection:
                return VNDetectFaceRectanglesRequest()
            case .textRecognition:
                return VNRecognizeTextRequest()
            case .barcodeDetection:
                return VNDetectBarcodesRequest()
            case .rectangleDetection:
                return VNDetectRectanglesRequest()
            case .all:
                return VNClassifyImageRequest()
            }
        }
    }

    // MARK: - Configuration

    /// Text recognition level
    public enum RecognitionLevel: Sendable, Equatable {
        case accurate
        case fast

        public var vnLevel: VNRequestTextRecognitionLevel {
            switch self {
            case .accurate: return .accurate
            case .fast: return .fast
            }
        }
    }

    public struct Config: Sendable {
        public let analysisTypes: [AnalysisType]
        public let classificationConfidenceThreshold: Float
        public let rectangleConfidenceThreshold: Float
        public let maxClassificationResults: Int
        public let useCPUOnly: Bool
        public let recognitionLanguages: [String]
        public let recognitionLevel: RecognitionLevel

        public init(
            analysisTypes: [AnalysisType] = [.classification],
            classificationConfidenceThreshold: Float = 0.5,
            rectangleConfidenceThreshold: Float = 0.5,
            maxClassificationResults: Int = 10,
            useCPUOnly: Bool = false,
            recognitionLanguages: [String] = ["en-US"],
            recognitionLevel: RecognitionLevel = .accurate
        ) {
            self.analysisTypes = analysisTypes
            self.classificationConfidenceThreshold = classificationConfidenceThreshold
            self.rectangleConfidenceThreshold = rectangleConfidenceThreshold
            self.maxClassificationResults = maxClassificationResults
            self.useCPUOnly = useCPUOnly
            self.recognitionLanguages = recognitionLanguages
            self.recognitionLevel = recognitionLevel
        }
    }

    // MARK: - Result Types

    public struct AnalysisResponse: Sendable, Equatable {
        public let results: [ImageAnalysisResponseHandler.AnalysisResult]
        public let imageSize: CGSize
        public let analysisTime: TimeInterval
        public let timestamp: Date

        public init(results: [ImageAnalysisResponseHandler.AnalysisResult], imageSize: CGSize, analysisTime: TimeInterval) {
            self.results = results
            self.imageSize = imageSize
            self.analysisTime = analysisTime
            self.timestamp = Date()
        }

        public var summary: String {
            results.map { $0.summary }.joined(separator: " | ")
        }

        public var isEmpty: Bool {
            results.isEmpty
        }
    }

    // MARK: - Properties

    private let config: Config
    private let responseHandler: ImageAnalysisResponseHandler

    // MARK: - Initialization

    public init(config: Config = Config()) {
        self.config = config
        self.responseHandler = ImageAnalysisResponseHandler(config: .init(
            classificationConfidenceThreshold: config.classificationConfidenceThreshold,
            objectDetectionConfidenceThreshold: config.rectangleConfidenceThreshold,
            maxClassificationResults: config.maxClassificationResults
        ))
    }

    // MARK: - Public Methods

    /// Analyze an image from a file path
    public func analyzeImage(at path: String) async throws -> AnalysisResponse {
        guard let image = NSImage(contentsOfFile: path) else {
            throw ImageAnalysisError.fileNotFound(path)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageAnalysisError.invalidImageFormat
        }

        return try await analyzeImage(cgImage)
    }

    /// Analyze a CGImage directly
    public func analyzeImage(_ cgImage: CGImage) async throws -> AnalysisResponse {
        let startTime = Date()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var requests: [VNRequest] = []

        for type in config.analysisTypes {
            switch type {
            case .classification:
                let classificationRequest = VNClassifyImageRequest()
                if config.useCPUOnly {
                    classificationRequest.usesCPUOnly = true
                }
                requests.append(classificationRequest)

            case .faceDetection:
                let faceRequest = VNDetectFaceRectanglesRequest()
                if config.useCPUOnly {
                    faceRequest.usesCPUOnly = true
                }
                requests.append(faceRequest)

            case .textRecognition:
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = config.recognitionLevel.vnLevel
                textRequest.recognitionLanguages = config.recognitionLanguages
                textRequest.usesLanguageCorrection = true
                if config.useCPUOnly {
                    textRequest.usesCPUOnly = true
                }
                requests.append(textRequest)

            case .barcodeDetection:
                let barcodeRequest = VNDetectBarcodesRequest()
                if config.useCPUOnly {
                    barcodeRequest.usesCPUOnly = true
                }
                requests.append(barcodeRequest)

            case .rectangleDetection:
                let rectangleRequest = VNDetectRectanglesRequest()
                if config.useCPUOnly {
                    rectangleRequest.usesCPUOnly = true
                }
                requests.append(rectangleRequest)

            case .all:
                let classificationRequest = VNClassifyImageRequest()
                requests.append(classificationRequest)

                let faceRequest = VNDetectFaceRectanglesRequest()
                requests.append(faceRequest)

                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = config.recognitionLevel.vnLevel
                textRequest.recognitionLanguages = config.recognitionLanguages
                requests.append(textRequest)

                let barcodeRequest = VNDetectBarcodesRequest()
                requests.append(barcodeRequest)

                let rectangleRequest = VNDetectRectanglesRequest()
                requests.append(rectangleRequest)
            }
        }

        try handler.perform(requests)

        var results: [ImageAnalysisResponseHandler.AnalysisResult] = []

        for request in requests {
            let result = await responseHandler.handleResults(from: request)
            results.append(result)
        }

        let analysisTime = Date().timeIntervalSince(startTime)

        return AnalysisResponse(
            results: results,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            analysisTime: analysisTime
        )
    }

    /// Analyze an NSImage
    public func analyzeImage(_ image: NSImage) async throws -> AnalysisResponse {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageAnalysisError.invalidImageFormat
        }
        return try await analyzeImage(cgImage)
    }

    // MARK: - Convenience Methods

    /// Quick classification of an image
    public func classifyImage(at path: String) async throws -> ImageAnalysisResponseHandler.ClassificationResult {
        let analysis = try await analyzeImage(at: path)
        guard let firstResult = analysis.results.first else {
            throw ImageAnalysisError.noClassificationResults
        }
        guard case .classification(let classification) = firstResult else {
            throw ImageAnalysisError.noClassificationResults
        }
        return classification
    }

    /// Quick text recognition from an image
    public func recognizeText(in image: NSImage) async throws -> ImageAnalysisResponseHandler.TextRecognitionResult {
        let config = Config(analysisTypes: [.textRecognition])
        let tool = ImageAnalysisTool(config: config)
        let analysis = try await tool.analyzeImage(image)
        guard let firstResult = analysis.results.first else {
            throw ImageAnalysisError.noTextResults
        }
        guard case .textRecognition(let textResult) = firstResult else {
            throw ImageAnalysisError.noTextResults
        }
        return textResult
    }

    /// Quick face detection
    public func detectFaces(in image: NSImage) async throws -> [ImageAnalysisResponseHandler.FaceObservation] {
        let config = Config(analysisTypes: [.faceDetection])
        let tool = ImageAnalysisTool(config: config)
        let analysis = try await tool.analyzeImage(image)
        guard case .faceDetection(let faces) = analysis.results.first else {
            throw ImageAnalysisError.noFaceResults
        }
        return faces
    }

    /// Quick barcode detection
    public func detectBarcodes(in image: NSImage) async throws -> [ImageAnalysisResponseHandler.BarcodeObservation] {
        let config = Config(analysisTypes: [.barcodeDetection])
        let tool = ImageAnalysisTool(config: config)
        let analysis = try await tool.analyzeImage(image)
        guard case .barcodeDetection(let barcodes) = analysis.results.first else {
            throw ImageAnalysisError.noBarcodeResults
        }
        return barcodes
    }
}

// MARK: - Errors

public enum ImageAnalysisError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidImageFormat
    case noClassificationResults
    case noTextResults
    case noFaceResults
    case noBarcodeResults
    case analysisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found at: \(path)"
        case .invalidImageFormat:
            return "Could not process image: invalid format"
        case .noClassificationResults:
            return "No classification results returned"
        case .noTextResults:
            return "No text recognition results returned"
        case .noFaceResults:
            return "No face detection results returned"
        case .noBarcodeResults:
            return "No barcode detection results returned"
        case .analysisFailed(let message):
            return "Image analysis failed: \(message)"
        }
    }
}
