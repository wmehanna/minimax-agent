import Foundation

/// Configuration for update check intervals.
///
/// This configures how often the application checks for available updates,
/// supporting different schedules for automatic vs manual checking.
public struct UpdateCheckConfiguration: Sendable, Codable {
    
    // MARK: - Check Interval
    
    /// How often to automatically check for updates
    public enum CheckInterval: Sendable, Codable, Equatable {
        /// Check every hour
        case hourly
        /// Check every day
        case daily
        /// Check every week
        case weekly
        /// Check every two weeks
        case biweekly
        /// Check with a custom interval
        case custom(TimeInterval)
        
        /// The time interval represented by this check interval
        public var timeInterval: TimeInterval {
            switch self {
            case .hourly:
                return 3600
            case .daily:
                return 86400
            case .weekly:
                return 604800
            case .biweekly:
                return 1209600
            case .custom(let interval):
                return interval
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case kind, customSeconds
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "hourly":
                self = .hourly
            case "daily":
                self = .daily
            case "weekly":
                self = .weekly
            case "biweekly":
                self = .biweekly
            case "custom":
                let seconds = try container.decode(TimeInterval.self, forKey: .customSeconds)
                self = .custom(seconds)
            default:
                self = .daily
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .hourly:
                try container.encode("hourly", forKey: .kind)
            case .daily:
                try container.encode("daily", forKey: .kind)
            case .weekly:
                try container.encode("weekly", forKey: .kind)
            case .biweekly:
                try container.encode("biweekly", forKey: .kind)
            case .custom(let interval):
                try container.encode("custom", forKey: .kind)
                try container.encode(interval, forKey: .customSeconds)
            }
        }
    }
    
    // MARK: - Configuration Properties
    
    /// The interval between automatic update checks
    public var checkInterval: CheckInterval
    
    /// Whether automatic update checking is enabled
    public var isAutomaticCheckEnabled: Bool
    
    /// Whether to check for updates on app launch
    public var checkOnLaunch: Bool
    
    /// The base URL for update checks (e.g., Sparkle AppCast endpoint)
    public var updateCheckURL: URL?
    
    /// User-agent string to send with update checks
    public var userAgent: String
    
    // MARK: - Initialization
    
    /// Default configuration with daily automatic checks
    public static let standard = UpdateCheckConfiguration(
        checkInterval: .daily,
        isAutomaticCheckEnabled: true,
        checkOnLaunch: true,
        updateCheckURL: nil,
        userAgent: "MiniMaxAgent/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"
    )
    
    /// Configuration for aggressive checking (useful during beta)
    public static let beta = UpdateCheckConfiguration(
        checkInterval: .hourly,
        isAutomaticCheckEnabled: true,
        checkOnLaunch: true,
        updateCheckURL: nil,
        userAgent: "MiniMaxAgent-Beta/1.0"
    )
    
    /// Configuration for minimal checking (privacy-conscious)
    public static let minimal = UpdateCheckConfiguration(
        checkInterval: .biweekly,
        isAutomaticCheckEnabled: false,
        checkOnLaunch: false,
        updateCheckURL: nil,
        userAgent: "MiniMaxAgent/1.0"
    )
    
    public init(
        checkInterval: CheckInterval = .daily,
        isAutomaticCheckEnabled: Bool = true,
        checkOnLaunch: Bool = true,
        updateCheckURL: URL? = nil,
        userAgent: String = "MiniMaxAgent/1.0"
    ) {
        self.checkInterval = checkInterval
        self.isAutomaticCheckEnabled = isAutomaticCheckEnabled
        self.checkOnLaunch = checkOnLaunch
        self.updateCheckURL = updateCheckURL
        self.userAgent = userAgent
    }
    
    // MARK: - Persistence
    
    /// Load configuration from UserDefaults
    public static func load() -> UpdateCheckConfiguration {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "MiniMaxAgent.UpdateCheckConfiguration") else {
            return .standard
        }
        do {
            return try JSONDecoder().decode(UpdateCheckConfiguration.self, from: data)
        } catch {
            return .standard
        }
    }
    
    /// Save configuration to UserDefaults
    public func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: "MiniMaxAgent.UpdateCheckConfiguration")
        } catch {
            // Log error in production
        }
    }
}
