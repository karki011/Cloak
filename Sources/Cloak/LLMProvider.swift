// LLM providers — streaming chat over SSE (Anthropic Messages API + OpenAI-compatible chat/completions).
import Foundation

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): return "Missing API key for \(name). Open settings (⌃⌥,) to add it."
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        }
    }
}

struct LLMMessage: Sendable {
    let role: String // "user" or "assistant"
    let content: String
}

protocol LLMProvider: Sendable {
    func stream(messages: [LLMMessage], system: String) -> AsyncThrowingStream<String, Error>
}

// MARK: - Shared SSE helper

struct SSEStream {
    /// Yields raw `data:` payloads (decoded JSON objects) from an SSE response.
    static func payloads(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.http(-1, "no HTTP response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw LLMError.http(http.statusCode, body)
                    }
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        guard line.hasPrefix("data:") else { continue }
                        var payload = line.dropFirst(5)
                        if payload.hasPrefix(" ") { payload = payload.dropFirst() }
                        if payload == "[DONE]" { break }
                        if let data = String(payload).data(using: .utf8) {
                            continuation.yield(data)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Anthropic

struct AnthropicProvider: LLMProvider {
    let apiKey: String
    let model: String

    func stream(messages: [LLMMessage], system: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw LLMError.missingAPIKey("Anthropic") }
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 2048,
                        "stream": true,
                        "system": system,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    ])
                    for try await payload in SSEStream.payloads(for: request) {
                        guard let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
                        guard obj["type"] as? String == "content_block_delta",
                              let delta = obj["delta"] as? [String: Any],
                              delta["type"] as? String == "text_delta",
                              let text = delta["text"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-compatible

struct OpenAICompatibleProvider: LLMProvider {
    let apiKey: String
    let baseURL: String
    let model: String
    var effort: String = "minimal"

    func stream(messages: [LLMMessage], system: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw LLMError.missingAPIKey("OpenAI-compatible") }
                    let base = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
                    guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
                        throw LLMError.http(-1, "invalid base URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    var body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [["role": "system", "content": system]]
                            + messages.map { ["role": $0.role, "content": $0.content] },
                    ]
                    // Latency tuning: GPT-5/o-series are reasoning models — reasoning inflates
                    // time-to-first-token 5-30x, so force minimal effort and cap output length.
                    if model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") {
                        body["reasoning_effort"] = effort
                        body["max_completion_tokens"] = 900
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    for try await payload in SSEStream.payloads(for: request) {
                        guard let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
