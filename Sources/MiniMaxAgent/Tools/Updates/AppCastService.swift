import Foundation

/// AppCast entry representing a single update version in the Sparkle feed.
///
/// AppCast is the XML-based update feed format used by Sparkle.
/// Each entry contains metadata about a specific release including
/// download URL, version info, and release notes.
public struct AppCastEntry: Sendable, Codable {
    
    // MARK: - Properties
    
    /// The version string (e.g., "1.2.3")
    public let version: String
    
    /// The short version string (e.g., "1.2")
    public let shortVersion: String
    
    /// Release notes in HTML or markdown
    public let releaseNotes: String?
    
    /// The URL to the update archive (.zip, .tar.gz, etc.)
    public let downloadURL: URL
    
    /// The size of the download in bytes
    public let downloadLength: Int64
    
    /// The MD5 checksum of the download archive
    public let md5Checksum: String?
    
    /// The SHA256 checksum of the download archive
    public let sha256Checksum: String?
    
    /// Publication date of this release
    public let publishDate: Date
    
    /// Minimum OS version required (e.g., "10.15")
    public let minimumSystemVersion: String?
    
    /// Maximum OS version supported (e.g., "14.0")
    public let maximumSystemVersion: String?
    
    /// Channel name (e.g., "stable", "beta")
    public let channel: String?
    
    /// The filename of the download
    public var filename: String {
        downloadURL.lastPathComponent
    }
    
    /// The file extension of the download
    public var fileExtension: String {
        downloadURL.pathExtension
    }
    
    // MARK: - Initialization
    
    public init(
        version: String,
        shortVersion: String,
        releaseNotes: String? = nil,
        downloadURL: URL,
        downloadLength: Int64,
        md5Checksum: String? = nil,
        sha256Checksum: String? = nil,
        publishDate: Date = Date(),
        minimumSystemVersion: String? = nil,
        maximumSystemVersion: String? = nil,
        channel: String? = nil
    ) {
        self.version = version
        self.shortVersion = shortVersion
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.downloadLength = downloadLength
        self.md5Checksum = md5Checksum
        self.sha256Checksum = sha256Checksum
        self.publishDate = publishDate
        self.minimumSystemVersion = minimumSystemVersion
        self.maximumSystemVersion = maximumSystemVersion
        self.channel = channel
    }
    
    // MARK: - XML Generation
    
    /// Generate the XML string for this AppCast entry (Sparkle 2.x / RSS 2.0 format)
    public func toXML() -> String {
        var xml = """
            <item>
                <title>MiniMaxAgent \(shortVersion)</title>
                <sparkle:version>\(escapeXML(version))</sparkle:version>
                <sparkle:shortVersionString>\(escapeXML(shortVersion))</sparkle:shortVersionString>
                <sparkle:releaseNotesLink><![CDATA[\(releaseNotes ?? "")]]></sparkle:releaseNotesLink>
                <enclosure url="\(escapeXML(downloadURL.absoluteString))" sparkle:length="\(downloadLength)" sparkle:md5Sum="\(escapeXML(md5Checksum ?? ""))" sparkle:sha256Checksum="\(escapeXML(sha256Checksum ?? ""))" type="application/octet-stream"/>
            
        """
        
        if let minVersion = minimumSystemVersion {
            xml += """
                <sparkle:minimumSystemVersion>\(escapeXML(minVersion))</sparkle:minimumSystemVersion>
            
            """
        }
        
        if let maxVersion = maximumSystemVersion {
            xml += """
                <sparkle:maximumSystemVersion>\(escapeXML(maxVersion))</sparkle:maximumSystemVersion>
            
            """
        }
        
        if let channel = channel {
            xml += """
                <sparkle:channel>\(escapeXML(channel))</sparkle:channel>
            
            """
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        xml += """
            <pubDate>\(dateFormatter.string(from: publishDate))</pubDate>
            </item>
            
            """
        
        return xml
    }
    
    /// Escape special XML characters
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Service for generating and managing Sparkle AppCast feeds.
///
/// AppCast feeds are XML documents that tell the Sparkle framework
/// about available updates. This service handles creating, updating,
/// and hosting the AppCast.
public actor AppCastService {
    
    // MARK: - Properties
    
    /// The base URL where updates are hosted
    public let baseURL: URL
    
    /// All entries in the AppCast, sorted by publish date (newest first)
    private var entries: [AppCastEntry]
    
    /// The deployment target minimum system version
    private let minimumSystemVersion: String?
    
    /// Maximum system version supported
    private let maximumSystemVersion: String?
    
    /// Default channel for entries
    private let defaultChannel: String?
    
    // MARK: - Initialization
    
    /// Initialize a new AppCast service
    /// - Parameters:
    ///   - baseURL: Base URL where updates are hosted
    ///   - minimumSystemVersion: Minimum macOS version required (e.g., "10.15")
    ///   - maximumSystemVersion: Maximum macOS version supported (e.g., "14.0")
    ///   - defaultChannel: Default channel name (e.g., "stable", "beta")
    public init(
        baseURL: URL,
        minimumSystemVersion: String? = "14.0",
        maximumSystemVersion: String? = nil,
        defaultChannel: String? = "stable"
    ) {
        self.baseURL = baseURL
        self.entries = []
        self.minimumSystemVersion = minimumSystemVersion
        self.maximumSystemVersion = maximumSystemVersion
        self.defaultChannel = defaultChannel
    }
    
    // MARK: - Entry Management
    
    /// Add a new entry to the AppCast
    /// - Parameter entry: The entry to add
    public func addEntry(_ entry: AppCastEntry) {
        entries.append(entry)
        sortEntries()
    }
    
    /// Remove an entry by version
    /// - Parameter version: The version string to remove
    /// - Returns: The removed entry if found
    @discardableResult
    public func removeEntry(version: String) -> AppCastEntry? {
        guard let index = entries.firstIndex(where: { $0.version == version }) else {
            return nil
        }
        return entries.remove(at: index)
    }
    
    /// Get entry by version
    /// - Parameter version: The version string to find
    /// - Returns: The entry if found
    public func entry(forVersion version: String) -> AppCastEntry? {
        entries.first { $0.version == version }
    }
    
    /// Get all entries
    public func allEntries() -> [AppCastEntry] {
        entries
    }
    
    /// Get entries for a specific channel
    /// - Parameter channel: The channel name
    /// - Returns: Entries filtered by channel
    public func entries(forChannel channel: String) -> [AppCastEntry] {
        entries.filter { $0.channel == channel }
    }
    
    /// Get the latest entry
    public func latestEntry() -> AppCastEntry? {
        entries.first
    }
    
    /// Sort entries by publish date (newest first)
    private func sortEntries() {
        entries.sort { $0.publishDate > $1.publishDate }
    }
    
    // MARK: - AppCast Generation
    
    /// Generate the complete AppCast XML document
    /// - Returns: Well-formed XML string representing the AppCast
    public func generateAppCastXML() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        var xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
                <channel>
                    <title>MiniMaxAgent Updates</title>
                    <link>\(baseURL.absoluteString)/appcast.xml</link>
                    <description>Software updates for MiniMaxAgent</description>
                    <language>en</language>
            
        """
        
        for entry in entries {
            xml += entry.toXML()
        }
        
        xml += """
                </channel>
            </rss>
            
        """
        
        return xml
    }
    
    /// Write the AppCast XML to a URL
    /// - Parameter url: The file URL to write to
    public func writeAppCast(to url: URL) async throws {
        let xml = generateAppCastXML()
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Entry Factory
    
    /// Create an AppCast entry from a downloaded archive
    /// - Parameters:
    ///   - version: Version string
    ///   - shortVersion: Short version string
    ///   - archiveURL: URL to the downloaded archive
    ///   - releaseNotes: Optional release notes HTML
    ///   - channel: Channel name
    /// - Returns: A new AppCast entry
    public func createEntry(
        version: String,
        shortVersion: String,
        archiveURL: URL,
        releaseNotes: String? = nil,
        channel: String? = nil
    ) async throws -> AppCastEntry {
        let (tempURL, _) = try await URLSession.shared.download(from: archiveURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Calculate checksums
        let fileData = try Data(contentsOf: tempURL)
        let md5 = calculateMD5(fileData)
        let sha256 = calculateSHA256(fileData)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        
        return AppCastEntry(
            version: version,
            shortVersion: shortVersion,
            releaseNotes: releaseNotes,
            downloadURL: archiveURL,
            downloadLength: fileSize,
            md5Checksum: md5,
            sha256Checksum: sha256,
            publishDate: Date(),
            minimumSystemVersion: minimumSystemVersion,
            maximumSystemVersion: maximumSystemVersion,
            channel: channel ?? defaultChannel
        )
    }
    
    private func calculateMD5(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func calculateSHA256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
