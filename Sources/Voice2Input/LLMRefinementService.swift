import Foundation

enum LLMRefinementError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "API Base URL 无效。"
        case .invalidResponse:
            return "LLM 返回内容不可解析。"
        case let .httpError(code, body):
            let suffix = body.isEmpty ? "" : " \(body)"
            return "LLM 请求失败 (\(code)).\(suffix)"
        }
    }
}

private enum LLMEndpointStyle {
    case openAICompatible
    case anthropicCompatible
}

final class LLMRefinementService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refine(text: String, configuration: LLMConfiguration) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let endpointStyle = endpointStyle(for: configuration.baseURL)
        var request = URLRequest(url: try endpointURL(from: configuration.baseURL, style: endpointStyle))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeBody(text: trimmed, model: configuration.model, style: endpointStyle)

        switch endpointStyle {
        case .openAICompatible:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicCompatible:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMRefinementError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMRefinementError.httpError(httpResponse.statusCode, body)
        }

        let parsed = try parseResponse(data, style: endpointStyle)
        return parsed.isEmpty ? text : parsed
    }

    func test(configuration: LLMConfiguration) async throws -> String {
        try await refine(
            text: "请保留 Python 和 JSON，不要改写已经正确的内容。",
            configuration: configuration
        )
    }

    private func endpointURL(from baseURL: String) throws -> URL {
        try endpointURL(from: baseURL, style: endpointStyle(for: baseURL))
    }

    private func endpointStyle(for baseURL: String) -> LLMEndpointStyle {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("/v1/messages") ||
            normalized.hasSuffix("/messages") ||
            normalized.contains("/coding") ||
            normalized.contains("anthropic") {
            return .anthropicCompatible
        }
        return .openAICompatible
    }

    private func endpointURL(from baseURL: String, style: LLMEndpointStyle) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw LLMRefinementError.invalidBaseURL
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LLMRefinementError.invalidBaseURL
        }

        let terminalPath: String
        switch style {
        case .openAICompatible:
            terminalPath = "/chat/completions"
        case .anthropicCompatible:
            terminalPath = "/v1/messages"
        }

        if components.path.hasSuffix(terminalPath) {
            return url
        }

        switch style {
        case .openAICompatible:
            if components.path.isEmpty {
                components.path = terminalPath
            } else if components.path.hasSuffix("/") {
                components.path += "chat/completions"
            } else {
                components.path += "/chat/completions"
            }
        case .anthropicCompatible:
            if components.path.isEmpty {
                components.path = terminalPath
            } else if components.path.hasSuffix("/v1") {
                components.path += "/messages"
            } else if components.path.hasSuffix("/") {
                components.path += "v1/messages"
            } else {
                components.path += "/v1/messages"
            }
        }

        guard let finalURL = components.url else {
            throw LLMRefinementError.invalidBaseURL
        }
        return finalURL
    }

    private func makeBody(text: String, model: String, style: LLMEndpointStyle) throws -> Data {
        let systemPrompt = """
        You correct raw speech recognition output very conservatively.
        Only fix obvious ASR mistakes.
        Preserve wording, order, punctuation, spacing style, and all content that already looks correct.
        Do not rewrite, polish, summarize, translate, or omit anything.
        Typical allowed fixes:
        - Chinese homophone recognition mistakes
        - English technical terms misrecognized as Chinese syllables, such as 配森 -> Python, 杰森 -> JSON
        If the text already looks correct, return it exactly unchanged.
        Return only the final corrected text.
        """

        var payload: [String: Any]
        switch style {
        case .openAICompatible:
            payload = [
                "model": model,
                "temperature": 0,
                "stream": false,
                "messages": [
                    [
                        "role": "system",
                        "content": systemPrompt
                    ],
                    [
                        "role": "user",
                        "content": text
                    ]
                ]
            ]
        case .anthropicCompatible:
            payload = [
                "model": model,
                "temperature": 0,
                "max_tokens": 512,
                "system": systemPrompt,
                "messages": [
                    [
                        "role": "user",
                        "content": text
                    ]
                ]
            ]
        }

        if shouldDisableKimiThinking(for: model) {
            payload["thinking"] = [
                "type": "disabled"
            ]
        }

        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func shouldDisableKimiThinking(for model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("kimi-k2.5")
    }

    private func parseResponse(_ data: Data, style: LLMEndpointStyle) throws -> String {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMRefinementError.invalidResponse
        }

        switch style {
        case .openAICompatible:
            guard let choices = jsonObject["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any] else {
                throw LLMRefinementError.invalidResponse
            }

            if let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let contentArray = message["content"] as? [[String: Any]] {
                let combined = contentArray.compactMap { $0["text"] as? String }.joined()
                return combined.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            throw LLMRefinementError.invalidResponse

        case .anthropicCompatible:
            if let content = jsonObject["content"] as? [[String: Any]] {
                let combined = content.compactMap { block -> String? in
                    guard let type = block["type"] as? String, type == "text" else {
                        return nil
                    }
                    return block["text"] as? String
                }.joined()

                if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return combined.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            throw LLMRefinementError.invalidResponse
        }
    }
}
