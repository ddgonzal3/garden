import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var agent: AgentService
    @State private var apiKey = ""
    @State private var model = ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic API Key")
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("sk-ant-api03-...", text: $apiKey)
                            } else {
                                SecureField("sk-ant-api03-...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .frame(width: 20)
                        }
                        .buttonStyle(.plain)
                        .help(showKey ? "Hide key" : "Reveal key")
                    }

                    if !apiKey.isEmpty {
                        Text(maskedKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("API")
            }

            Section {
                Picker("Model", selection: $model) {
                    Text("Haiku 4.5 — cheapest, fast").tag("claude-haiku-4-5")
                    Text("Sonnet 4.6 — balanced").tag("claude-sonnet-4-6")
                    Text("Opus 4.6 — smartest").tag("claude-opus-4-6")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Model")
            }

            Section {
                HStack {
                    Spacer()
                    Button(action: save) {
                        HStack(spacing: 4) {
                            if saved {
                                Image(systemName: "checkmark")
                                Text("Saved")
                            } else {
                                Text("Save")
                            }
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .onAppear {
            apiKey = agent.apiKey
            model = agent.model
        }
    }

    private var hasChanges: Bool {
        apiKey != agent.apiKey || model != agent.model
    }

    private var maskedKey: String {
        guard apiKey.count > 8 else { return String(repeating: "*", count: apiKey.count) }
        let prefix = apiKey.prefix(7)
        let suffix = apiKey.suffix(4)
        let middle = String(repeating: "*", count: min(apiKey.count - 11, 20))
        return "\(prefix)\(middle)\(suffix)"
    }

    private func save() {
        agent.saveApiKey(apiKey)
        agent.model = model
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
