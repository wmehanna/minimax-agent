import Foundation
import Vision

/// Handles the parsing and processing of Vision framework image analysis responses
/// Converts raw Vision observations into standardized, app-friendly formats
public actor ImageAnalysisResponseHandler {

    // MARK: - Response Types

    /// Unified response type for all image analysis operations
    public enum AnalysisResult: Sendable, Equatable {
        case classification(ClassificationResult)
        case objectDetection([DetectedObject])
        case faceDetection([FaceObservation])
        case textRecognition(TextRecognitionResult)
        case barcodeDetection([BarcodeObservation])
        case custom(String)

        /// Human-readable summary of the result
        public var summary: String {
            switch self {
            case .classification(let result):
                return "Classified \(result.observations.count) items, top: \(result.topLabel ?? "unknown")"
            case .objectDetection(let objects):
                return "Detected \(objects.count) objects"
            case .faceDetection(let faces):
                return "Detected \(faces.count) faces"
            case .textRecognition(let result):
                return "Recognized \(result.text), confidence: \(String(format: "%.1f", result.confidence * 100))%"
            case .barcodeDetection(let barcodes):
                return "Detected \(barcodes.count) barcodes"
            case .custom(let message):
                return message
            }
        }
    }

    /// Result of image classification
    public struct ClassificationResult: Sendable, Equatable {
        public let observations: [ClassificationObservation]
        public let topLabel: String?
        public let topConfidence: Float?

        public init(observations: [ClassificationObservation], topLabel: String? = nil, topConfidence: Float? = nil) {
            self.observations = observations
            self.topLabel = topLabel ?? observations.first?.identifier
            self.topConfidence = topConfidence ?? observations.first?.confidence
        }
    }

    /// A single classification observation
    public struct ClassificationObservation: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let identifier: String
        public let confidence: Float
        public let parentIdentifier: String?

        public init(id: UUID = UUID(), identifier: String, confidence: Float, parentIdentifier: String? = nil) {
            self.id = id
            self.identifier = identifier
            self.confidence = confidence
            self.parentIdentifier = parentIdentifier
        }
    }

    /// Result of object detection
    public struct DetectedObject: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let label: String
        public let confidence: Float
        public let boundingBox: CGRect
        public let normalizedBoundingBox: CGRect

        public init(id: UUID = UUID(), label: String, confidence: Float, boundingBox: CGRect, normalizedBoundingBox: CGRect) {
            self.id = id
            self.label = label
            self.confidence = confidence
            self.boundingBox = boundingBox
            self.normalizedBoundingBox = normalizedBoundingBox
        }

        /// Converts normalized coordinates to image coordinates
        public func boundingBoxInImage(imageSize: CGSize) -> CGRect {
            return CGRect(
                x: normalizedBoundingBox.origin.x * imageSize.width,
                y: (1 - normalizedBoundingBox.origin.y - normalizedBoundingBox.height) * imageSize.height,
                width: normalizedBoundingBox.width * imageSize.width,
                height: normalizedBoundingBox.height * imageSize.height
            )
        }
    }

    /// Result of face detection
    public struct FaceObservation: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let boundingBox: CGRect
        public let normalizedBoundingBox: CGRect
        public let roll: Float?
        public let pitch: Float?
        public let yaw: Float?
        public let landmarks: [FaceLandmark]?

        public init(
            id: UUID = UUID(),
            boundingBox: CGRect,
            normalizedBoundingBox: CGRect,
            roll: Float? = nil,
            pitch: Float? = nil,
            yaw: Float? = nil,
            landmarks: [FaceLandmark]? = nil
        ) {
            self.id = id
            self.boundingBox = boundingBox
            self.normalizedBoundingBox = normalizedBoundingBox
            self.roll = roll
            self.pitch = pitch
            self.yaw = yaw
            self.landmarks = landmarks
        }
    }

    /// Face landmark types
    public struct FaceLandmark: Sendable, Equatable {
        public let type: LandmarkType
        public let points: [CGPoint]

        public enum LandmarkType: String, Sendable {
            case leftEye
            case rightEye
            case nose
            case outerLips
            case faceContour
            case leftEyebrow
            case rightEyebrow
            case noseCrest
            case medianLine
        }
    }

    /// Result of text recognition (OCR)
    public struct TextRecognitionResult: Sendable, Equatable {
        public let text: String
        public let confidence: Float
        public let observations: [TextObservation]

        public init(text: String, confidence: Float, observations: [TextObservation] = []) {
            self.text = text
            self.confidence = confidence
            self.observations = observations
        }
    }

    /// Individual text observation
    public struct TextObservation: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let text: String
        public let confidence: Float
        public let boundingBox: CGRect

        public init(id: UUID = UUID(), text: String, confidence: Float, boundingBox: CGRect) {
            self.id = id
            self.text = text
            self.confidence = confidence
            self.boundingBox = boundingBox
        }
    }

    /// Result of barcode detection
    public struct BarcodeObservation: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let payload: String
        public let symbology: String
        public let confidence: Float
        public let boundingBox: CGRect

        public init(id: UUID = UUID(), payload: String, symbology: String, confidence: Float, boundingBox: CGRect) {
            self.id = id
            self.payload = payload
            self.symbology = symbology
            self.confidence = confidence
            self.boundingBox = boundingBox
        }
    }

    // MARK: - Handler Configuration

    public struct Config: Sendable {
        /// Minimum confidence threshold for classification results
        public let classificationConfidenceThreshold: Float

        /// Minimum confidence threshold for object detection
        public let objectDetectionConfidenceThreshold: Float

        /// Maximum number of classification results to return
        public let maxClassificationResults: Int

        /// Whether to include face landmarks
        public let includeFaceLandmarks: Bool

        /// Whether to include roll/pitch/yaw for faces
        public let includeFaceAngles: Bool

        public init(
            classificationConfidenceThreshold: Float = 0.5,
            objectDetectionConfidenceThreshold: Float = 0.5,
            maxClassificationResults: Int = 10,
            includeFaceLandmarks: Bool = true,
            includeFaceAngles: Bool = true
        ) {
            self.classificationConfidenceThreshold = classificationConfidenceThreshold
            self.objectDetectionConfidenceThreshold = objectDetectionConfidenceThreshold
            self.maxClassificationResults = maxClassificationResults
            self.includeFaceLandmarks = includeFaceLandmarks
            self.includeFaceAngles = includeFaceAngles
        }
    }

    // MARK: - Properties

    private let config: Config

    // MARK: - Initialization

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Process Vision framework classification results
    public func handleClassificationResults(_ results: [VNClassificationObservation]) -> ClassificationResult {
        let filtered = results
            .filter { $0.confidence >= config.classificationConfidenceThreshold }
            .prefix(config.maxClassificationResults)

        let observations = filtered.map { observation in
            ClassificationObservation(
                identifier: observation.identifier,
                confidence: observation.confidence,
                parentIdentifier: nil // observation.parent is iOS 17+ / macOS 14+ only
            )
        }

        return ClassificationResult(observations: observations)
    }

    /// Process Vision framework rectangle detection results
    public func handleRectangleDetectionResults(_ results: [VNRectangleObservation]) -> [DetectedObject] {
        return results
            .filter { $0.confidence >= config.objectDetectionConfidenceThreshold }
            .map { observation in
                DetectedObject(
                    label: "rectangle",
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox,
                    normalizedBoundingBox: observation.boundingBox
                )
            }
    }

    /// Process Vision framework face detection results
    public func handleFaceDetectionResults(_ results: [VNFaceObservation]) -> [FaceObservation] {
        return results.map { observation in
            var landmarks: [FaceLandmark]?

            if config.includeFaceLandmarks, let faceLandmarks = observation.landmarks {
                landmarks = parseFaceLandmarks(faceLandmarks)
            }

            return FaceObservation(
                boundingBox: observation.boundingBox,
                normalizedBoundingBox: observation.boundingBox,
                roll: config.includeFaceAngles ? observation.roll?.floatValue : nil,
                pitch: config.includeFaceAngles ? observation.pitch?.floatValue : nil,
                yaw: config.includeFaceAngles ? observation.yaw?.floatValue : nil,
                landmarks: landmarks
            )
        }
    }

    /// Process Vision framework text recognition results
    public func handleTextRecognitionResults(_ results: [VNRecognizedTextObservation]) -> TextRecognitionResult {
        let observations = results.map { observation -> TextObservation in
            let topCandidate = observation.topCandidates(1).first
            return TextObservation(
                text: topCandidate?.string ?? "",
                confidence: topCandidate?.confidence ?? 0,
                boundingBox: observation.boundingBox
            )
        }

        let fullText = observations.map { $0.text }.joined(separator: " ")
        let avgConfidence = observations.isEmpty ? 0 : observations.map { $0.confidence }.reduce(0, +) / Float(observations.count)

        return TextRecognitionResult(
            text: fullText,
            confidence: avgConfidence,
            observations: observations
        )
    }

    /// Process Vision framework barcode detection results
    public func handleBarcodeDetectionResults(_ results: [VNBarcodeObservation]) -> [BarcodeObservation] {
        return results.map { observation in
            BarcodeObservation(
                payload: observation.payloadStringValue ?? "",
                symbology: observation.symbology.rawValue,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    /// Process any Vision request results generically
    public func handleResults(from request: VNRequest) -> AnalysisResult {
        guard let results = request.results else {
            return .custom("No results found")
        }

        // Try each observation type
        if let classificationResults = results as? [VNClassificationObservation] {
            return .classification(handleClassificationResults(classificationResults))
        }

        if let rectangleResults = results as? [VNRectangleObservation] {
            return .objectDetection(handleRectangleDetectionResults(rectangleResults))
        }

        if let faceResults = results as? [VNFaceObservation] {
            return .faceDetection(handleFaceDetectionResults(faceResults))
        }

        if let textResults = results as? [VNRecognizedTextObservation] {
            return .textRecognition(handleTextRecognitionResults(textResults))
        }

        if let barcodeResults = results as? [VNBarcodeObservation] {
            return .barcodeDetection(handleBarcodeDetectionResults(barcodeResults))
        }

        return .custom("Unknown result type with \(results.count) observations")
    }

    // MARK: - Private Methods

    private func parseFaceLandmarks(_ landmarks: VNFaceLandmarks2D) -> [FaceLandmark] {
        var result: [FaceLandmark] = []

        if let leftEye = landmarks.leftEye {
            result.append(FaceLandmark(type: .leftEye, points: convertPoints(leftEye)))
        }

        if let rightEye = landmarks.rightEye {
            result.append(FaceLandmark(type: .rightEye, points: convertPoints(rightEye)))
        }

        if let nose = landmarks.nose {
            result.append(FaceLandmark(type: .nose, points: convertPoints(nose)))
        }

        if let outerLips = landmarks.outerLips {
            result.append(FaceLandmark(type: .outerLips, points: convertPoints(outerLips)))
        }

        if let faceContour = landmarks.faceContour {
            result.append(FaceLandmark(type: .faceContour, points: convertPoints(faceContour)))
        }

        if let leftEyebrow = landmarks.leftEyebrow {
            result.append(FaceLandmark(type: .leftEyebrow, points: convertPoints(leftEyebrow)))
        }

        if let rightEyebrow = landmarks.rightEyebrow {
            result.append(FaceLandmark(type: .rightEyebrow, points: convertPoints(rightEyebrow)))
        }

        if let noseCrest = landmarks.noseCrest {
            result.append(FaceLandmark(type: .noseCrest, points: convertPoints(noseCrest)))
        }

        if let medianLine = landmarks.medianLine {
            result.append(FaceLandmark(type: .medianLine, points: convertPoints(medianLine)))
        }

        return result
    }

    private func convertPoints(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
        return region.normalizedPoints.map { point in
            CGPoint(x: point.x, y: point.y)
        }
    }
}
