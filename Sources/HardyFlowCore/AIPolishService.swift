import Foundation

/// Modes/tags for AI polishing.
public enum PolishTag: String, CaseIterable, Identifiable, Sendable {
    case noTag = "No-Tag"
    case email = "Email"
    case aiPrompt = "AI-Prompt"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .noTag:
            return "No-Tag"
        case .email:
            return "Email"
        case .aiPrompt:
            return "AI-Prompt"
        }
    }
    
    public var iconName: String {
        switch self {
        case .noTag:
            return "tag.slash"
        case .email:
            return "envelope.fill"
        case .aiPrompt:
            return "sparkles"
        }
    }
    
    public var systemInstruction: String {
        switch self {
        case .noTag:
            return """
            You are an expert voice-to-text transcription polisher.
            Your task is to fix grammatical errors, punctuation, casing, remove accidental filler words ("um", "uh", "you know", "like"), and correct speech recognition mishearings.
            Preserve the user's original words, meaning, and voice faithfully.
            Do NOT add conversational replies, commentary, questions, or quotes. Output ONLY the polished text.
            """
        case .email:
            return """
            You are an expert executive communication assistant.
            Transform the user's dictated stream of thoughts into a polished, professional email.
            Structure it cleanly with an appropriate greeting, concise body paragraphs, bullet points if multiple items are mentioned, and a professional closing sign-off.
            Do NOT include conversational meta-text like "Here is your email:". Output ONLY the formatted email content.
            """
        case .aiPrompt:
            return """
            You are a world-class prompt engineer for AI systems and developer CLI tools (such as Claude Code, Gemini CLI, Cursor, ChatGPT).
            Transform the user's raw dictated concept into a structured, high-clarity, high-impact prompt.
            Format it with clear sections where applicable:
            - **Objective**: The primary goal
            - **Context**: Relevant background details
            - **Instructions / Steps**: Clear execution instructions
            - **Constraints**: Critical rules or formatting requirements
            Do NOT wrap with meta commentary. Output ONLY the structured prompt.
            """
        }
    }
}

/// Actor managing asynchronous OpenAI-compatible Llama 3 API communication.
public actor AIPolishService {
    public static let shared = AIPolishService()
    
    private let session: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25.0
        configuration.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: configuration)
    }
    
    public enum PolishError: LocalizedError, Sendable {
        case emptyInput
        case missingConfiguration
        case invalidResponse(statusCode: Int, message: String)
        case decodingFailed
        case networkError(String)
        
        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Dictated text is empty. Speak or type something first."
            case .missingConfiguration:
                return "No API key found. Add LLAMA_API_KEY to your .env file."
            case .invalidResponse(let statusCode, let message):
                return "AI API returned error \(statusCode): \(message)"
            case .decodingFailed:
                return "Failed to parse AI response."
            case .networkError(let msg):
                return "Network connection error: \(msg)"
            }
        }
    }
    
    /// Polishes raw text using the specified tag and configuration.
    public func polish(
        text: String,
        tag: PolishTag,
        config: AIConfiguration
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PolishError.emptyInput
        }
        
        var request = URLRequest(url: config.apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Only set Bearer token if not local or placeholder
        if !config.apiKey.isEmpty && config.apiKey != "local-no-key-required" {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": tag.systemInstruction],
                ["role": "user", "content": trimmed]
            ],
            "temperature": config.temperature,
            "max_tokens": 1500
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw PolishError.networkError("JSON serialization error: \(error.localizedDescription)")
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let host = config.apiUrl.host ?? "endpoint"
            let isLocal = host.contains("localhost") || host.contains("127.0.0.1")
            if isLocal {
                throw PolishError.networkError(
                    "Cannot connect to local Ollama server at \(config.apiUrl.absoluteString). Ensure Ollama is installed and running (`ollama serve`)."
                )
            } else {
                throw PolishError.networkError(
                    "Could not connect to AI service at \(host): \(error.localizedDescription). Check your internet connection or .env settings."
                )
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolishError.invalidResponse(statusCode: -1, message: "Invalid HTTP response from AI service.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var detail = ""
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
                    detail = msg
                } else if let msg = json["message"] as? String {
                    detail = msg
                }
            }
            if detail.isEmpty {
                detail = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            }
            
            let host = config.apiUrl.host ?? ""
            if httpResponse.statusCode == 401 {
                if host.contains("groq.com") {
                    throw PolishError.invalidResponse(
                        statusCode: 401,
                        message: "Invalid Groq API Key. Groq keys start with 'gsk_'. Get a free key at https://console.groq.com or use local Ollama in .env."
                    )
                } else if host.contains("openai.com") {
                    throw PolishError.invalidResponse(
                        statusCode: 401,
                        message: "Invalid OpenAI API Key. OpenAI keys start with 'sk-'. Please check LLAMA_API_KEY in .env."
                    )
                } else {
                    throw PolishError.invalidResponse(
                        statusCode: 401,
                        message: "Authentication failed (401): \(detail). Check your API key in .env."
                    )
                }
            } else if httpResponse.statusCode == 404 {
                if host.contains("localhost") || host.contains("127.0.0.1") {
                    throw PolishError.invalidResponse(
                        statusCode: 404,
                        message: "Model '\(config.model)' not found in Ollama. Run 'ollama run \(config.model)' in Terminal, or update LLAMA_MODEL in .env."
                    )
                } else {
                    throw PolishError.invalidResponse(
                        statusCode: 404,
                        message: "Model '\(config.model)' not found at \(config.apiUrl.absoluteString). Check LLAMA_MODEL in .env."
                    )
                }
            }
            
            throw PolishError.invalidResponse(statusCode: httpResponse.statusCode, message: detail)
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw PolishError.decodingFailed
            }
        } catch {
            throw PolishError.decodingFailed
        }
    }
}
