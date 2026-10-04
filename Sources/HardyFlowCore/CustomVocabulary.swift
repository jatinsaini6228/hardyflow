import Foundation

/// Comprehensive domain vocabulary for HardyFlow speech recognition,
/// incorporating technical terminology, Indian English / Hinglish colloquialisms,
/// and automated phonetic corrections for high-frequency acoustic confusions.
public enum CustomVocabulary {
    
    // MARK: - Technical & Modern Software Engineering Vocabulary (2026)
    public static let techTerms: [String] = [
        // UI & Frontend Frameworks
        "popup", "pop-up", "pop up", "modal", "dialog", "navbar", "dropdown", "sidebar",
        "tooltip", "toast", "chip", "waveform", "carousel", "accordion", "breadcrumb",
        "viewport", "responsive", "frontend", "backend", "fullstack", "devops",
        "Next.js", "React", "Vue", "Angular", "Svelte", "SolidJS", "Astro", "Nuxt",
        "Tailwind", "Tailwind CSS", "shadcn", "Radix", "Chakra", "TanStack", "Zustand", "Redux",
        
        // Architecture, APIs & Runtimes
        "REST", "API", "GraphQL", "gRPC", "WebSocket", "webhook", "endpoint", "microservices",
        "monolith", "serverless", "lambda", "pubsub", "Kafka", "RabbitMQ", "middleware",
        "async", "await", "coroutine", "thread", "concurrency", "multithreading", "event loop",
        "Node.js", "Bun", "Deno", "Turborepo", "tRPC", "Prisma", "Drizzle", "FastAPI", "Pydantic",
        "Celery", "gunicorn", "uvicorn", "WebAssembly", "WASM", "WebGPU", "eBPF",
        
        // Cloud, Containers & DevOps
        "AWS", "GCP", "Azure", "Cloudflare", "Vercel", "Supabase", "Kubernetes", "k8s",
        "Docker", "container", "Helm", "ArgoCD", "Terraform", "Ansible", "Prometheus",
        "Grafana", "OpenTelemetry", "Datadog", "Nginx", "Caddy", "Traefik",
        "PostgreSQL", "Postgres", "MySQL", "MariaDB", "MongoDB", "Redis", "SQLite", "DynamoDB",
        
        // Developer Tools & Version Control
        "Git", "GitHub", "GitLab", "Bitbucket", "commit", "rebase", "merge", "pull request",
        "checkout", "stash", "branch", "CI/CD", "pipeline", "linter", "debugger", "compiler",
        "refactor", "bugfix", "hotfix", "VS Code", "Xcode", "Terminal", "Bash", "Zsh", "Homebrew",
        "Postman", "Insomnia", "OAuth", "JWT", "Bcrypt", "Zod",
        
        // Languages
        "Swift", "SwiftUI", "AppKit", "macOS", "iOS", "Python", "JavaScript", "TypeScript",
        "Golang", "Rust", "C++", "Kotlin", "Flutter", "Dart", "PHP",
        
        // Modern AI & Machine Learning Ecosystem
        "LLM", "Llama", "Llama 3", "Llama 3.3", "ChatGPT", "OpenAI", "Claude", "Gemini", "Anthropic",
        "DeepSeek", "Groq", "Ollama", "vLLM", "Hugging Face", "transformer", "embedding",
        "RAG", "vector database", "fine-tuning", "inference", "prompt", "prompt engineering", "token",
        "LangChain", "LlamaIndex", "LoRA", "PEFT", "Quantization", "GGUF", "AWQ",
        "Qdrant", "Pinecone", "Chroma", "Milvus", "Weaviate", "Cursor", "Copilot",
        
        // Product & Project Management
        "Agile", "Scrum", "Sprint", "Standup", "Jira", "Confluence", "Notion", "Slack",
        "HardyFlow", "Hey Hardy", "Wisperflow", "dictation", "transcription", "hotkey"
    ]
    
    // MARK: - Gen-Z & Modern Internet Slang Dictionary
    public static let genZSlangs: [String] = [
        "rizz", "no cap", "cap", "bet", "slay", "bussin", "delulu", "glow up",
        "lowkey", "highkey", "vibe check", "main character", "rent free", "drip",
        "ate", "cooked", "let him cook", "let me cook", "iykyk", "goat", "stan",
        "spill the tea", "touch grass", "it's giving", "simp", "mid", "caught in 4k",
        "ratio", "valid", "sheesh", "fr fr", "period", "gaslighting", "gatekeep",
        "girlboss", "skibidi", "fanum tax", "gyatt", "sigma", "npc", "brain rot",
        "unc", "aura", "crash out", "lock in", "cook", "flex", "sus", "bop",
        "snatched", "banger", "hits different", "understood the assignment", "living rent free",
        "deadass", "facts", "based", "yeet", "cheugy", "w", "l"
    ]
    
    // MARK: - Indian English, Slang & Hinglish Expressions
    public static let indianExpressions: [String] = [
        "jugaad", "chalo", "achha", "theek hai", "arrey", "yaar", "fundae", "funda",
        "bindaas", "pukka", "lakh", "crore", "lakhs", "crores", "aadhaar", "UPI",
        "bhai", "bhaiya", "didi", "namaste", "chai", "desi", "babu", "sahib",
        "prepone", "preponed", "revert back", "do the needful", "out of station",
        "passed out", "updation", "intimation", "batchmate", "doubt", "cousin brother",
        "cousin sister", "today only", "first class", "tight slap", "god promise",
        "timepass", "chumma", "matlab", "shukriya", "dhanyawad", "zindabad",
        "mast", "badhiya", "tension", "faadu", "jhakaas", "bawa", "scene",
        "kya baat hai", "chinta mat karo", "sahih hai", "ekdum", "shanti", "hustle",
        "bhaijaan", "guru", "boss", "maal", "bakwaas", "fundas", "bindas", "arre"
    ]
    
    // MARK: - Combined Contextual Strings for SFSpeechAudioBufferRecognitionRequest
    public static var allContextualStrings: [String] {
        return techTerms + indianExpressions + genZSlangs
    }
    
    // MARK: - Wake Word Acoustic Contextual Bias
    public static let wakeWordContextualStrings: [String] = [
        "Hey Hardy", "Hi Hardy", "OK Hardy", "Hello Hardy", "HardyFlow",
        "hey hardy", "hi hardy", "ok hardy", "hello hardy", "hardy", "hardik"
    ]
    
    // MARK: - Phonetic Auto-Correction Rules
    // Corrects common acoustic/phonetic misrecognitions specific to Indian accents, tech words, and Gen-Z slangs
    private static let phoneticReplacements: [(pattern: String, replacement: String)] = [
        // UI & "papa" -> "popup" corrections
        (#"(?i)\bthe\s+papa\b"#, "the popup"),
        (#"(?i)\bopen\s+the\s+papa\b"#, "open the popup"),
        (#"(?i)\bclose\s+the\s+papa\b"#, "close the popup"),
        (#"(?i)\bpapa\s+card\b"#, "popup card"),
        (#"(?i)\bpapa\s+window\b"#, "popup window"),
        (#"(?i)\bmove\s+the\s+papa\b"#, "move the popup"),
        (#"(?i)\bpapa\s+is\b"#, "popup is"),
        (#"(?i)\bapp\s+papa\b"#, "app popup"),
        
        // Gen-Z Slang Phonetic Confusions
        (#"(?i)\bno\s+cup\b"#, "no cap"),
        (#"(?i)\bno\s+cab\b"#, "no cap"),
        (#"(?i)\bno\s+cap\b"#, "no cap"),
        (#"(?i)\bfor\s+real\s+for\s+real\b"#, "fr fr"),
        (#"(?i)\bfr\s+fr\b"#, "fr fr"),
        (#"(?i)\bde\s*lulu\b"#, "delulu"),
        (#"(?i)\bdeloooloo\b"#, "delulu"),
        (#"(?i)\bbussing\b"#, "bussin"),
        (#"(?i)\bbus\s+in\b"#, "bussin"),
        (#"(?i)\blet\s+him\s+cook\b"#, "let him cook"),
        (#"(?i)\blet\s+me\s+cook\b"#, "let me cook"),
        (#"(?i)\bski\s*bidi\b"#, "skibidi"),
        (#"(?i)\bski\s*biddy\b"#, "skibidi"),
        (#"(?i)\bfanum\s+tax\b"#, "Fanum tax"),
        (#"(?i)\bvibe\s+chek\b"#, "vibe check"),
        (#"(?i)\bglowup\b"#, "glow up"),
        
        // Indian Expressions Phonetic Confusions
        (#"(?i)\bthek\s+hai\b"#, "theek hai"),
        (#"(?i)\btick\s+hai\b"#, "theek hai"),
        (#"(?i)\bjugaar\b"#, "jugaad"),
        (#"(?i)\bjugad\b"#, "jugaad"),
        (#"(?i)\bacha\b"#, "achha"),
        (#"(?i)\bachha\b"#, "achha"),
        (#"(?i)\barre\b"#, "arrey"),
        
        // Modern Tech & AI Term Corrections
        (#"(?i)\bsink\s+await\b"#, "async await"),
        (#"(?i)\bsink\s+function\b"#, "async function"),
        (#"(?i)\bkuber\s*net(?:ies|ease|is)\b"#, "Kubernetes"),
        (#"(?i)\bgit\s*hub\b"#, "GitHub"),
        (#"(?i)\bgit\s*lab\b"#, "GitLab"),
        (#"(?i)\bvs\s*code\b"#, "VS Code"),
        (#"(?i)\bmac\s*os\b"#, "macOS"),
        (#"(?i)\bhardy\s*flow\b"#, "HardyFlow"),
        (#"(?i)\bwisper\s*flow\b"#, "Wisperflow"),
        (#"(?i)\bllama\s*three\b"#, "Llama 3"),
        (#"(?i)\bllama\s*3\.3\b"#, "Llama 3.3"),
        (#"(?i)\bpost\s*gress?\b"#, "Postgres"),
        (#"(?i)\bpost\s*gre\s*sql\b"#, "PostgreSQL"),
        (#"(?i)\bnext\s*js\b"#, "Next.js"),
        (#"(?i)\btail\s*wind(?:\s*css)?\b"#, "Tailwind CSS"),
        (#"(?i)\bsupa\s*base\b"#, "Supabase"),
        (#"(?i)\bver\s*cel\b"#, "Vercel"),
        (#"(?i)\bpris\s*ma\b"#, "Prisma"),
        (#"(?i)\blang\s*chain\b"#, "LangChain"),
        (#"(?i)\bllama\s*index\b"#, "LlamaIndex"),
        (#"(?i)\bdeep\s*seek\b"#, "DeepSeek"),
        (#"(?i)\bco\s*pilot\b"#, "Copilot"),
        (#"(?i)\bv\s*llm\b"#, "vLLM"),
        (#"(?i)\bg\s*guf\b"#, "GGUF"),
        (#"(?i)\bpine\s*cone\b"#, "Pinecone"),
        (#"(?i)\bq\s*drant\b"#, "Qdrant"),
        (#"(?i)\bweb\s*gpu\b"#, "WebGPU"),
        (#"(?i)\bweb\s*asm\b"#, "WASM"),
        (#"(?i)\be\s*bpf\b"#, "eBPF")
    ]
    
    /// Applies regex-based phonetic corrections to raw transcriptions.
    public static func applyPhoneticCorrections(_ input: String) -> String {
        var result = input
        for (pattern, replacement) in phoneticReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        return result
    }
}
