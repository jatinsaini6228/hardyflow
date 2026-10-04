import Foundation

/// Lightweight environment configuration loader for HardyFlow.
/// Reads `.env` files from project directories, user home directory, and app bundles.
public struct AIConfiguration: Equatable, Sendable {
    public let apiKey: String
    public let apiUrl: URL
    public let model: String
    public let temperature: Double
    
    public init(
        apiKey: String,
        apiUrl: URL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
        model: String = "llama-3.3-70b-versatile",
        temperature: Double = 0.3
    ) {
        self.apiKey = apiKey
        self.apiUrl = apiUrl
        self.model = model
        self.temperature = temperature
    }
}

public enum EnvLoader {
    
    /// Searches known candidate locations for the `.env` file and loads AI configuration.
    public static func loadAIConfiguration() -> AIConfiguration? {
        let envDict = loadAllEnvVariables()
        
        // Check for any supported API key variable
        let apiKey = envDict["LLAMA_API_KEY"]
            ?? envDict["GROQ_API_KEY"]
            ?? envDict["OPENAI_API_KEY"]
            ?? envDict["OLLAMA_API_KEY"]
            ?? envDict["AI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["LLAMA_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"]
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_API_KEY"]
        
        var urlString = envDict["LLAMA_API_URL"]
            ?? envDict["OLLAMA_API_URL"]
            ?? envDict["AI_API_URL"]
            ?? ProcessInfo.processInfo.environment["LLAMA_API_URL"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_API_URL"]
            ?? ""
        
        // If user set OLLAMA_HOST (e.g. "localhost:11434" or "http://localhost:11434")
        if urlString.isEmpty, let host = envDict["OLLAMA_HOST"] ?? ProcessInfo.processInfo.environment["OLLAMA_HOST"], !host.isEmpty {
            let cleanHost = host.hasPrefix("http") ? host : "http://\(host)"
            urlString = "\(cleanHost)/v1/chat/completions"
        }
        
        // If still empty, default to Groq cloud
        if urlString.isEmpty {
            urlString = "https://api.groq.com/openai/v1/chat/completions"
        }
        
        // Normalize Ollama endpoint URLs if user entered root host without /v1/chat/completions
        if (urlString.contains(":11434") || urlString.contains("localhost")) && !urlString.contains("/v1/chat/completions") && !urlString.contains("/api/chat") {
            let stripped = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            urlString = "\(stripped)/v1/chat/completions"
        }
        
        var model = envDict["LLAMA_MODEL"]
            ?? envDict["OLLAMA_MODEL"]
            ?? envDict["AI_MODEL"]
            ?? ProcessInfo.processInfo.environment["LLAMA_MODEL"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_MODEL"]
            ?? ""
        
        if model.isEmpty {
            if urlString.contains(":11434") || urlString.contains("localhost") {
                model = "llama3.2"
            } else {
                model = "llama-3.3-70b-versatile"
            }
        }
        
        let tempString = envDict["LLAMA_TEMPERATURE"]
            ?? envDict["AI_TEMPERATURE"]
            ?? ProcessInfo.processInfo.environment["LLAMA_TEMPERATURE"]
        let temperature = Double(tempString ?? "") ?? 0.3
        
        guard let validUrl = URL(string: urlString) else {
            return nil
        }
        
        // If an API key exists, use it
        if let key = apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIConfiguration(apiKey: key, apiUrl: validUrl, model: model, temperature: temperature)
        } else if urlString.contains("localhost") || urlString.contains("127.0.0.1") || urlString.contains(":11434") {
            // Local endpoints (Ollama/llama.cpp) run natively without required API keys
            return AIConfiguration(apiKey: "local-no-key-required", apiUrl: validUrl, model: model, temperature: temperature)
        }
        
        return nil
    }
    
    /// Loads key-value pairs from candidate .env file paths.
    public static func loadAllEnvVariables() -> [String: String] {
        var results: [String: String] = [:]
        
        let candidatePaths = [
            // 1. Current working directory .env
            FileManager.default.currentDirectoryPath + "/.env",
            // 2. Project directory within mac-workspace
            "/Users/jatinsaini/Downloads/mac-workspace/projects/wisperflow/.env",
            // 3. User home folder .hardyflow config
            NSHomeDirectory() + "/.hardyflow/.env",
            NSHomeDirectory() + "/.hardyflow.env",
            // 4. Bundle resources path if packaged inside
            Bundle.main.path(forResource: ".env", ofType: nil) ?? ""
        ]
        
        for path in candidatePaths where !path.isEmpty {
            if FileManager.default.fileExists(atPath: path) {
                if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    let parsed = parseEnvContent(contents)
                    for (k, v) in parsed {
                        results[k] = v
                    }
                    print("📄 [EnvLoader] Loaded environment variables from: \(path)")
                    break
                }
            }
        }
        
        return results
    }
    
    /// Parses raw .env string into key-value dictionary, ignoring comments and whitespace.
    public static func parseEnvContent(_ content: String) -> [String: String] {
        var vars: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                
                // Strip enclosing single or double quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    if value.count >= 2 {
                        value = String(value.dropFirst().dropLast())
                    }
                }
                vars[key] = value
            }
        }
        return vars
    }
}
