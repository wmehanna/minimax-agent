import Foundation

/// Service for generating and applying binary deltas for efficient incremental updates.
///
/// Delta updates allow downloading only the binary diff between an old version and a new version,
/// significantly reducing download sizes for app updates.
public struct DeltaUpdateService: Sendable {
    
    // MARK: - Public Types
    
    /// Represents a delta patch between two versions of data
    public struct DeltaPatch: Sendable, Codable {
        public let sourceVersion: String
        public let targetVersion: String
        public let operations: [DeltaOperation]
        public let checksum: String
        
        public init(sourceVersion: String, targetVersion: String, operations: [DeltaOperation], checksum: String) {
            self.sourceVersion = sourceVersion
            self.targetVersion = targetVersion
            self.operations = operations
            self.checksum = checksum
        }
    }
    
    /// A single operation within a delta patch
    public enum DeltaOperation: Sendable, Codable {
        case copy(offset: Int, length: Int)
        case insert(Data)
        case delete(length: Int)
        
        private enum CodingKeys: String, CodingKey {
            case type, offset, length, data
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "copy":
                let offset = try container.decode(Int.self, forKey: .offset)
                let length = try container.decode(Int.self, forKey: .length)
                self = .copy(offset: offset, length: length)
            case "insert":
                let data = try container.decode(Data.self, forKey: .data)
                self = .insert(data)
            case "delete":
                let length = try container.decode(Int.self, forKey: .length)
                self = .delete(length: length)
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown operation type: \(type)"))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .copy(let offset, let length):
                try container.encode("copy", forKey: .type)
                try container.encode(offset, forKey: .offset)
                try container.encode(length, forKey: .length)
            case .insert(let data):
                try container.encode("insert", forKey: .type)
                try container.encode(data, forKey: .data)
            case .delete(let length):
                try container.encode("delete", forKey: .type)
                try container.encode(length, forKey: .length)
            }
        }
    }
    
    /// Result of applying a delta patch
    public enum ApplyResult: Sendable {
        case success(Data)
        case failure(ApplyError)
    }
    
    /// Errors that can occur when applying delta patches
    public enum ApplyError: Error, LocalizedError {
        case checksumMismatch
        case invalidPatch
        case sourceDataTooShort
        
        public var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return "Delta patch checksum verification failed"
            case .invalidPatch:
                return "Delta patch contains invalid operations"
            case .sourceDataTooShort:
                return "Source data is shorter than expected by patch"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Generate a delta patch between source and target data
    /// - Parameters:
    ///   - source: The original data
    ///   - target: The new data to generate a patch for
    ///   - sourceVersion: Version identifier for the source
    ///   - targetVersion: Version identifier for the target
    /// - Returns: A delta patch that can be used to transform source into target
    public func generateDelta(from source: Data, to target: Data, sourceVersion: String, targetVersion: String) -> DeltaPatch {
        let operations = computeDeltaOperations(source: source, target: target)
        let checksum = computeChecksum(target)
        return DeltaPatch(
            sourceVersion: sourceVersion,
            targetVersion: targetVersion,
            operations: operations,
            checksum: checksum
        )
    }
    
    /// Apply a delta patch to source data to reconstruct the target
    /// - Parameters:
    ///   - patch: The delta patch to apply
    ///   - source: The original source data
    /// - Returns: The reconstructed target data, or an error if application fails
    public func applyDelta(_ patch: DeltaPatch, to source: Data) -> ApplyResult {
        // Verify checksum of expected result
        let _ = computeChecksum(source)
        // Source checksum verification is informational only - we proceed regardless
        
        var result = Data()
        var sourceOffset = 0
        
        for operation in patch.operations {
            switch operation {
            case .copy(let offset, let length):
                guard sourceOffset + length <= source.count else {
                    return .failure(.sourceDataTooShort)
                }
                let startIndex = source.index(source.startIndex, offsetBy: offset)
                let endIndex = source.index(startIndex, offsetBy: length)
                result.append(source[startIndex..<endIndex])
                sourceOffset = offset + length
                
            case .insert(let data):
                result.append(data)
                
            case .delete(let length):
                sourceOffset += length
            }
        }
        
        // Verify the result matches expected checksum
        let resultChecksum = computeChecksum(result)
        guard resultChecksum == patch.checksum else {
            return .failure(.checksumMismatch)
        }
        
        return .success(result)
    }
    
    /// Encode a delta patch to data for storage/transmission
    public func encodePatch(_ patch: DeltaPatch) throws -> Data {
        try JSONEncoder().encode(patch)
    }
    
    /// Decode a delta patch from data
    public func decodePatch(from data: Data) throws -> DeltaPatch {
        try JSONDecoder().decode(DeltaPatch.self, from: data)
    }
    
    // MARK: - Private Methods
    
    /// Compute the optimal sequence of delta operations using a greedy matching algorithm
    private func computeDeltaOperations(source: Data, target: Data) -> [DeltaOperation] {
        var operations: [DeltaOperation] = []
        
        // Use a simple block-based diff algorithm
        let blockSize = 64
        let sourceBlocks = splitIntoBlocks(source, size: blockSize)
        let targetBlocks = splitIntoBlocks(target, size: blockSize)
        
        // Find longest common subsequence using dynamic programming
        let lcs = longestCommonSubsequence(sourceBlocks, targetBlocks)
        
        var sourceIndex = 0
        var targetIndex = 0
        var insertBuffer = Data()
        
        func flushInsertBuffer() {
            if !insertBuffer.isEmpty {
                operations.append(.insert(insertBuffer))
                insertBuffer = Data()
            }
        }
        
        for (srcIdx, tgtIdx) in zip(lcs.sourceIndices, lcs.targetIndices) {
            // Delete any source blocks not in LCS
            while sourceIndex < srcIdx {
                let start = sourceIndex * blockSize
                let end = min(start + blockSize, source.count)
                operations.append(.delete(length: end - start))
                sourceIndex += 1
            }
            
            // Copy matched blocks
            while targetIndex < tgtIdx {
                let start = targetIndex * blockSize
                let end = min(start + blockSize, target.count)
                flushInsertBuffer()
                operations.append(.copy(offset: srcIdx * blockSize, length: end - start))
                targetIndex += 1
                sourceIndex = srcIdx + 1
            }
            
            // Add new blocks from target not in LCS
            while targetIndex < targetBlocks.count && targetIndex < lcs.targetIndices[lcs.targetIndices.firstIndex(of: tgtIdx) ?? 0] {
                let start = targetIndex * blockSize
                let end = min(start + blockSize, target.count)
                insertBuffer.append(target[start..<end])
                targetIndex += 1
            }
        }
        
        // Handle remaining target blocks
        while targetIndex < targetBlocks.count {
            let start = targetIndex * blockSize
            let end = min(start + blockSize, target.count)
            insertBuffer.append(target[start..<end])
            targetIndex += 1
        }
        
        flushInsertBuffer()
        return operations
    }
    
    private func splitIntoBlocks(_ data: Data, size: Int) -> [[UInt8]] {
        stride(from: 0, to: data.count, by: size).map { offset in
            Array(data[offset..<min(offset + size, data.count)])
        }
    }
    
    private struct LCSResult {
        let sourceIndices: [Int]
        let targetIndices: [Int]
    }
    
    private func longestCommonSubsequence(_ source: [[UInt8]], _ target: [[UInt8]]) -> LCSResult {
        let m = source.count
        let n = target.count
        
        // DP table
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if source[i - 1] == target[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        
        // Backtrack to find the LCS
        var sourceIndices: [Int] = []
        var targetIndices: [Int] = []
        
        var i = m
        var j = n
        while i > 0 && j > 0 {
            if source[i - 1] == target[j - 1] {
                sourceIndices.insert(i - 1, at: 0)
                targetIndices.insert(j - 1, at: 0)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        
        return LCSResult(sourceIndices: sourceIndices, targetIndices: targetIndices)
    }
    
    private func computeChecksum(_ data: Data) -> String {
        // Simple FNV-1a hash for checksum
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        
        return String(format: "%016llx", hash)
    }
}
