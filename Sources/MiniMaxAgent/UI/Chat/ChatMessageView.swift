import SwiftUI
import AppKit

/// A SwiftUI view representing a single chat message with a copy button
public struct ChatMessageView: View {
    let message: ChatMessage
    let showTimestamp: Bool
    let timestampFormat: TimestampFormat
    @State private var isCopied = false
    @State private var isHovered = false

    public enum TimestampFormat: String, CaseIterable, Sendable {
        case time12h = "h:mm a"      // 3:45 PM
        case time24h = "HH:mm"       // 15:45
        case relative = "relative"   // "just now", "5 min ago"
        case full = "full"           // "Mar 29, 2026 at 3:45 PM"
        case dayTime = "dayTime"     // "Today 3:45 PM", "Yesterday 3:45 PM", "Mar 29 3:45 PM"
    }

    public init(
        message: ChatMessage,
        showTimestamp: Bool = true,
        timestampFormat: TimestampFormat = .dayTime
    ) {
        self.message = message
        self.showTimestamp = showTimestamp
        self.timestampFormat = timestampFormat
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // System messages are centered
            if message.sender == .system {
                Spacer(minLength: 60)
            }
            // User messages: no leading spacer (right-aligned)
            // Assistant messages: no leading spacer (left-aligned)

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Message bubble
                messageBubble

                // Timestamp
                if showTimestamp {
                    timestampView
                }
            }

            if message.sender == .system {
                Spacer(minLength: 60)
            }
            // User messages: trailing spacer (right-aligned)
            if message.sender == .user {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var messageBubble: some View {
        ZStack(alignment: .topTrailing) {
            Text(message.content)
                .font(message.sender == .system ? .footnote : .body)
                .fontWeight(message.sender == .system ? .regular : .none)
                .italic(message.sender == .system)
                .foregroundColor(foregroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .cornerRadius(message.sender == .system ? 8 : 12)
                .textSelection(.enabled)

            // Copy button (appears on hover or for assistant messages)
            if isHovered || message.sender == .assistant {
                copyButton
                    .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var copyButton: some View {
        Button(action: copyContent) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(4)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }

    private var timestampView: some View {
        HStack(spacing: 4) {
            Text(formattedTimestamp)
                .font(.caption2)
                .foregroundColor(.secondary)

            if isCopied {
                Text("Copied!")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            // Status indicator for user messages
            if message.sender == .user {
                statusIndicator
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch message.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 12, height: 12)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.red)
                .help("Message failed to send")
        }
    }

    private var formattedTimestamp: String {
        switch timestampFormat {
        case .time12h:
            return timeFormatter(format: "h:mm a").string(from: message.timestamp)
        case .time24h:
            return timeFormatter(format: "HH:mm").string(from: message.timestamp)
        case .relative:
            return relativeTimestamp
        case .full:
            return fullTimestamp
        case .dayTime:
            return dayTimeTimestamp
        }
    }

    private func timeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }

    private var relativeTimestamp: String {
        let now = Date()
        let interval = now.timeIntervalSince(message.timestamp)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 172800 {
            return "yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        } else {
            return dayTimeTimestamp
        }
    }

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    private var dayTimeTimestamp: String {
        let now = Date()
        let calendar = Calendar.current

        let nowStart = calendar.startOfDay(for: now)
        let messageStart = calendar.startOfDay(for: message.timestamp)

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if messageStart == nowStart {
            return "Today \(formatter.string(from: message.timestamp))"
        } else if messageStart == calendar.date(byAdding: .day, value: -1, to: nowStart) {
            return "Yesterday \(formatter.string(from: message.timestamp))"
        } else if calendar.isDate(message.timestamp, equalTo: now, toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE h:mm a" // "Sunday 3:45 PM"
            return formatter.string(from: message.timestamp)
        } else if calendar.isDate(message.timestamp, equalTo: now, toGranularity: .year) {
            formatter.dateFormat = "MMM d h:mm a" // "Mar 29 3:45 PM"
            return formatter.string(from: message.timestamp)
        } else {
            return fullTimestamp
        }
    }

    private var foregroundColor: Color {
        switch message.sender {
        case .user:
            return .white
        case .assistant:
            // AI messages use a distinct secondary blue-ish color
            return Color(NSColor.systemBlue).opacity(0.9)
        case .system:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch message.sender {
        case .user:
            return Color.accentColor
        case .assistant:
            // AI messages have a subtle blue-tinted background
            return Color(NSColor.systemBlue).opacity(0.08)
        case .system:
            return Color(NSColor.windowBackgroundColor).opacity(0.5)
        }
    }

    private func copyContent() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
        #endif
    }
}

// MARK: - Date Separator

/// A date separator view to group messages by day
public struct DateSeparatorView: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        HStack {
            line
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            line
        }
        .padding(.vertical, 8)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ChatMessageView_Previews: PreviewProvider {
    static let now = Date()

    static var previews: some View {
        VStack(spacing: 16) {
            ChatMessageView(
                message: ChatMessage(
                    content: "Hello! How can I help you today?",
                    sender: .assistant,
                    timestamp: now
                ),
                timestampFormat: .dayTime
            )

            ChatMessageView(
                message: ChatMessage(
                    content: "I need help with my code",
                    sender: .user,
                    timestamp: now.addingTimeInterval(-60)
                ),
                timestampFormat: .relative
            )

            ChatMessageView(
                message: ChatMessage(
                    content: "System notification here",
                    sender: .system,
                    timestamp: now.addingTimeInterval(-3600)
                ),
                timestampFormat: .full
            )

            DateSeparatorView(date: now)
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
#endif
