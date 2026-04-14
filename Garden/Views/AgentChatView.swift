import SwiftUI

struct AgentChatView: View {
    @EnvironmentObject var agent: AgentService
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(agent.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if agent.isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: agent.messages.count) { _, _ in
                    withAnimation {
                        if agent.isLoading {
                            proxy.scrollTo("loading")
                        } else if let lastId = agent.messages.last?.id {
                            proxy.scrollTo(lastId)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask Garden...", text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }
                    .disabled(agent.isLoading)

                if agent.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
        }
        .overlay {
            if !agent.hasApiKey {
                ContentUnavailableView {
                    Label("API Key Required", systemImage: "key")
                } description: {
                    Text("Add your Anthropic API key in Settings (Cmd+,)")
                }
            }
        }
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""

        Task {
            await agent.send(text)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(.init(message.content)) // Renders markdown
                .textSelection(.enabled)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
