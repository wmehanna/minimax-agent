import SwiftUI
import AppKit

/// A SwiftUI view representing the entire chat interface
public struct ChatView: View {
    @Binding var messages: [ChatMessage]
    @State private var scrollProxy: ScrollViewProxy?

    public init(messages: Binding<[ChatMessage]>) {
        self._messages = messages
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 16)
            }
            .onAppear {
                self.scrollProxy = proxy
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Hosting Controller

#if os(macOS)
/// NSViewController that hosts the ChatView SwiftUI view
public class ChatViewController: NSViewController {
    private var messages: [ChatMessage] = []
    private var hostingView: NSHostingView<AnyView>?

    public override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        self.view = containerView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupHostingView()
    }

    private func setupHostingView() {
        let chatView = AnyView(ChatView(messages: .constant(messages)))
        let hosting = NSHostingView(rootView: chatView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingView = hosting
    }

    /// Update the messages displayed in the chat
    public func updateMessages(_ newMessages: [ChatMessage]) {
        self.messages = newMessages
        let chatView = AnyView(ChatView(messages: .constant(messages)))
        hostingView?.rootView = chatView
    }

    /// Add a new message to the chat
    public func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updateMessages(messages)
    }
}
#endif

// MARK: - Preview

#if DEBUG
struct ChatView_Previews: PreviewProvider {
    static var messages: [ChatMessage] = [
        ChatMessage(content: "Hello! How can I help you today?", sender: .assistant),
        ChatMessage(content: "I need help with my Swift code", sender: .user),
        ChatMessage(content: "Of course! What specifically do you need help with?", sender: .assistant),
        ChatMessage(content: "Can you explain async/await?", sender: .user),
        ChatMessage(content: "async/await is Swift's way of handling asynchronous operations...", sender: .assistant)
    ]

    static var previews: some View {
        ChatView(messages: .constant(messages))
            .frame(width: 400, height: 500)
    }
}
#endif
