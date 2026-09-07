// Settings — UserDefaults for non-secret prefs, Keychain for API keys; SwiftUI settings view.
import SwiftUI
import AppKit

enum ProviderKind: String, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openAICompatible = "OpenAI-compatible"
    var id: String { rawValue }
}

struct SettingsStore: Sendable {
    static let shared = SettingsStore()

    static let anthropicModels = ["claude-opus-4-7", "claude-sonnet-4-5", "claude-haiku-4-5"]
    static let openAIModels = ["chat-latest", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra", "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1-nano"]
    static let effortLevels = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]

    private var defaults: UserDefaults { .standard }

    var provider: ProviderKind {
        ProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
    }
    var anthropicModel: String {
        defaults.string(forKey: "anthropicModel").flatMap { $0.isEmpty ? nil : $0 } ?? "claude-sonnet-4-5"
    }
    var openAIBaseURL: String {
        defaults.string(forKey: "openAIBaseURL").flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.openai.com/v1"
    }
    var openAIModel: String {
        defaults.string(forKey: "openAIModel").flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-5-mini"
    }
    var reasoningEffort: String {
        defaults.string(forKey: "reasoningEffort").flatMap { $0.isEmpty ? nil : $0 } ?? "none"
    }

    var activeModel: String {
        provider == .anthropic ? anthropicModel : openAIModel
    }

    func makeProvider() -> any LLMProvider {
        switch provider {
        case .anthropic:
            return AnthropicProvider(apiKey: Keychain.get(account: "anthropic") ?? "", model: anthropicModel)
        case .openAICompatible:
            return OpenAICompatibleProvider(apiKey: Keychain.get(account: "openai") ?? "",
                                            baseURL: openAIBaseURL,
                                            model: openAIModel,
                                            effort: reasoningEffort)
        }
    }
}

struct SettingsView: View {
    @AppStorage("provider") private var providerRaw: String = ProviderKind.anthropic.rawValue
    @AppStorage("anthropicModel") private var anthropicModel: String = "claude-sonnet-4-5"
    @AppStorage("openAIBaseURL") private var openAIBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("openAIModel") private var openAIModel: String = "gpt-5-mini"
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "none"
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("overlayOpacity") private var overlayOpacity = 0.92
    @AppStorage("themeMode") private var themeMode = "auto"

    // Keep a custom value (e.g. a Groq model name) selectable in the dropdown.
    static func withCurrent(_ list: [String], current: String) -> [String] {
        list.contains(current) || current.isEmpty ? list : list + [current]
    }
    @State private var anthropicKey: String = Keychain.get(account: "anthropic") ?? ""
    @State private var openAIKey: String = Keychain.get(account: "openai") ?? ""
    @State private var savedFlash = false

    private var provider: ProviderKind {
        ProviderKind(rawValue: providerRaw) ?? .anthropic
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(ProviderKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
            Section("API Keys (stored in Keychain)") {
                SecureField("Anthropic API key", text: $anthropicKey)
                SecureField("OpenAI-compatible API key", text: $openAIKey)
                HStack {
                    Button("Save Keys") { saveKeys() }
                    if savedFlash { Text("Saved").foregroundStyle(.green).font(.caption) }
                }
            }
            Section("Models") {
                Picker("Anthropic model", selection: $anthropicModel) {
                    ForEach(Self.withCurrent(SettingsStore.anthropicModels, current: anthropicModel), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("Base URL", text: $openAIBaseURL)
                Picker("OpenAI-compatible model", selection: $openAIModel) {
                    ForEach(Self.withCurrent(SettingsStore.openAIModels, current: openAIModel), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .help("Works with Groq, OpenRouter, Ollama, etc. via Base URL — type a custom name there and it appears here")
                Picker("Reasoning effort", selection: $reasoningEffort) {
                    ForEach(SettingsStore.effortLevels, id: \.self) { Text($0).tag($0) }
                }
                .help("GPT-5/o-series only. minimal = fastest replies; higher = deeper reasoning")
            }
            Section("Appearance") {
                Picker("Card theme", selection: $themeMode) {
                    Text("Auto").tag("auto")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
                .help("Auto samples what's behind the overlay and flips text color to stay readable")
                HStack {
                    Text("Overlay opacity")
                    Slider(value: $overlayOpacity, in: 0.35...1.0)
                    Text("\(Int(overlayOpacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                }
                .help("Lower = more see-through, so the overlay blocks less of what's behind it")
            }
            Section("Debugging") {
                Toggle("Debug mode (visible to screenshots, diagnostics line)", isOn: $debugMode)
                    .help("Takes effect on next launch. Lets you screenshot the overlay to triage issues.")
                Button("Restart App Now") { restartApp() }
                    .controlSize(.small)
                    .help("Relaunches GhostOverlay with current settings applied")
            }
            Section("App") {
                Button("Quit Cloak", role: .destructive) { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .help("Also available anywhere via ⌃⌥Q")
            }
            Section("Hotkeys") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌃⌥Space — show/hide overlay")
                    Text("⌃⌥Return — send question")
                    Text("Hold Right-⌥ — push-to-talk")
                    Text("⌃⌥M — toggle listening")
                    Text("⌃⌥L — always-on listening (system audio)")
                    Text("⌃⌥E — summarize meeting + save")
                    Text("⌃⌥Q — quit app")
                    Text("⌃⌥, — open settings")
                    Text("⎋ — hide overlay")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveKeys() {
        Keychain.set(anthropicKey, account: "anthropic")
        Keychain.set(openAIKey, account: "openai")
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
    }
}
