import AppKit
import SwiftUI

@MainActor
final class LLMSettingsViewModel: ObservableObject {
    @Published var baseURL: String
    @Published var apiKey: String
    @Published var model: String
    @Published var statusMessage = ""
    @Published var isTesting = false

    private let settings: AppSettings
    private let refinementService: LLMRefinementService

    init(settings: AppSettings, refinementService: LLMRefinementService) {
        self.settings = settings
        self.refinementService = refinementService
        baseURL = settings.llmConfiguration.baseURL
        apiKey = settings.llmConfiguration.apiKey
        model = settings.llmConfiguration.model
    }

    func save() {
        settings.updateLLMConfiguration(currentConfiguration)
        statusMessage = "Saved."
    }

    func test() {
        statusMessage = ""
        isTesting = true
        let configuration = currentConfiguration

        Task {
            do {
                let response = try await refinementService.test(configuration: configuration)
                await MainActor.run {
                    self.statusMessage = "Test ok: \(response)"
                    self.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.isTesting = false
                }
            }
        }
    }

    private var currentConfiguration: LLMConfiguration {
        LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
    }
}

@MainActor
final class LLMSettingsWindowController: NSWindowController {
    init(settings: AppSettings, refinementService: LLMRefinementService) {
        let viewModel = LLMSettingsViewModel(settings: settings, refinementService: refinementService)
        let contentView = LLMSettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LLM Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 520, height: 260))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct LLMSettingsView: View {
    @ObservedObject var viewModel: LLMSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                labeledField(title: "API Base URL", text: $viewModel.baseURL, placeholder: "https://api.example.com/v1")
                labeledField(title: "API Key", text: $viewModel.apiKey, placeholder: "sk-...")
                labeledField(title: "Model", text: $viewModel.model, placeholder: "gpt-4.1-mini / kimi-k2.5")
            }

            Text("Supports OpenAI-compatible chat completions and Anthropic-compatible messages endpoints. Kimi env fallback is supported.")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(viewModel.isTesting ? "Testing…" : "Test") {
                    viewModel.test()
                }
                .disabled(viewModel.isTesting)

                Button("Save") {
                    viewModel.save()
                }

                Spacer()
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 260)
    }

    private func labeledField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
