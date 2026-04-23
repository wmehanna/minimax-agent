import Foundation

/// Represents a single message in the chat
public struct ChatMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public let content: String
    public let sender: Sender
    public let timestamp: Date
    public let status: Status

    public enum Sender: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public enum Status: Codable, Sendable {
        case sending
        case sent
        case failed(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "sending": self = .sending
            case "sent": self = .sent
            case "failed": self = .failed(try container.decode(String.self, forKey: .reason))
            default: self = .sent
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .sending: try container.encode("sending", forKey: .type)
            case .sent: try container.encode("sent", forKey: .type)
            case .failed(let reason): try container.encode("failed", forKey: .type); try container.encode(reason, forKey: .reason)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, reason
        }
    }

    public init(
        id: UUID = UUID(),
        content: String,
        sender: Sender,
        timestamp: Date = Date(),
        status: Status = .sent
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.status = status
    }
}
