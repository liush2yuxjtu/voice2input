import Foundation

struct LLMConfiguration: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class AppSettings {
    private enum Keys {
        static let selectedLanguage = "selectedLanguage"
        static let llmEnabled = "llmEnabled"
        static let llmBaseURL = "llmBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
    }

    private enum EnvironmentKeys {
        static let directBaseURL = "VOICE2INPUT_LLM_BASE_URL"
        static let directAPIKey = "VOICE2INPUT_LLM_API_KEY"
        static let directModel = "VOICE2INPUT_LLM_MODEL"
        static let openAIBaseURL = "OPENAI_BASE_URL"
        static let openAIAPIBaseURL = "OPENAI_API_BASE_URL"
        static let openAIAPIKey = "OPENAI_API_KEY"
        static let openAIModel = "OPENAI_MODEL"
        static let anthropicBaseURL = "ANTHROPIC_BASE_URL"
        static let anthropicAPIKey = "ANTHROPIC_AUTH_TOKEN"
        static let anthropicModel = "ANTHROPIC_MODEL"
    }

    private let defaults: UserDefaults
    private let environment: [String: String]

    var selectedLanguage: LanguageOption {
        didSet {
            defaults.set(selectedLanguage.rawValue, forKey: Keys.selectedLanguage)
        }
    }

    var llmEnabled: Bool {
        didSet {
            defaults.set(llmEnabled, forKey: Keys.llmEnabled)
        }
    }

    private(set) var llmConfiguration: LLMConfiguration

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.environment = environment
        selectedLanguage = LanguageOption(
            rawValue: defaults.string(forKey: Keys.selectedLanguage) ?? LanguageOption.simplifiedChinese.rawValue
        ) ?? .simplifiedChinese
        let resolvedConfiguration = Self.resolvedLLMConfiguration(defaults: defaults, environment: environment)
        llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? resolvedConfiguration.isComplete
        llmConfiguration = resolvedConfiguration
        bootstrapEnvironmentBackfillIfNeeded(configuration: resolvedConfiguration)
    }

    func updateLLMConfiguration(_ configuration: LLMConfiguration) {
        llmConfiguration = configuration
        setOrRemove(configuration.baseURL, forKey: Keys.llmBaseURL)
        setOrRemove(configuration.apiKey, forKey: Keys.llmAPIKey)
        setOrRemove(configuration.model, forKey: Keys.llmModel)
    }

    private func setOrRemove(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }

    private static func resolvedLLMConfiguration(defaults: UserDefaults, environment: [String: String]) -> LLMConfiguration {
        let storedBaseURL = defaults.string(forKey: Keys.llmBaseURL) ?? ""
        let storedAPIKey = defaults.string(forKey: Keys.llmAPIKey) ?? ""
        let storedModel = defaults.string(forKey: Keys.llmModel) ?? ""

        let baseURL = firstNonEmpty([
            storedBaseURL,
            environment[EnvironmentKeys.directBaseURL],
            environment[EnvironmentKeys.openAIAPIBaseURL],
            environment[EnvironmentKeys.openAIBaseURL],
            environment[EnvironmentKeys.anthropicBaseURL]
        ])

        let apiKey = firstNonEmpty([
            storedAPIKey,
            environment[EnvironmentKeys.directAPIKey],
            environment[EnvironmentKeys.openAIAPIKey],
            environment[EnvironmentKeys.anthropicAPIKey]
        ])

        var model = firstNonEmpty([
            storedModel,
            environment[EnvironmentKeys.directModel],
            environment[EnvironmentKeys.openAIModel],
            environment[EnvironmentKeys.anthropicModel]
        ])

        if model.isEmpty, isKimiConfiguration(baseURL: baseURL, apiKey: apiKey) {
            model = "kimi-k2.5"
        }

        return LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    private func bootstrapEnvironmentBackfillIfNeeded(configuration: LLMConfiguration) {
        if defaults.string(forKey: Keys.llmBaseURL).isNilOrEmpty {
            setOrRemove(configuration.baseURL, forKey: Keys.llmBaseURL)
        }

        if defaults.string(forKey: Keys.llmAPIKey).isNilOrEmpty {
            setOrRemove(configuration.apiKey, forKey: Keys.llmAPIKey)
        }

        if defaults.string(forKey: Keys.llmModel).isNilOrEmpty {
            setOrRemove(configuration.model, forKey: Keys.llmModel)
        }
    }

    private static func isKimiConfiguration(baseURL: String, apiKey: String) -> Bool {
        let lowerBaseURL = baseURL.lowercased()
        return lowerBaseURL.contains("moonshot") ||
            lowerBaseURL.contains("api.kimi.com") ||
            apiKey.lowercased().hasPrefix("sk-kimi-")
    }

    private static func firstNonEmpty(_ values: [String?]) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
