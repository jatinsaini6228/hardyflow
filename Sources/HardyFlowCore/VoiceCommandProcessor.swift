import Foundation

/// Analyzes and cleans speech recognition text streams, executing voice correction commands.
/// Specifically detects "NO NO NO Remove" (case/punctuation-insensitive) to discard user mistakes in real-time.
public struct VoiceCommandProcessor: Sendable {
    
    /// Result returned after processing a transcribed string.
    public struct ProcessResult: Equatable, Sendable {
        public let text: String
        public let didRemove: Bool
        public let wordsRemovedCount: Int
        
        public init(text: String, didRemove: Bool, wordsRemovedCount: Int) {
            self.text = text
            self.didRemove = didRemove
            self.wordsRemovedCount = wordsRemovedCount
        }
    }
    
    // Regular expression matching "NO NO NO" variations (with optional "REMOVE")
    private static let removalRegex: NSRegularExpression = {
        let pattern = #"(?i)\bno[\s,]+no[\s,]+no(\b|[\s,]+remove\b)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()
    
    public init() {}
    
    /// Processes a raw transcription string, applies custom phonetic auto-corrections,
    /// expands spoken macro snippets, removes any "NO NO NO" trigger sequences, and applies smart text normalization.
    public func process(_ rawText: String) -> ProcessResult {
        let corrected = CustomVocabulary.applyPhoneticCorrections(rawText)
        let withSnippets = SnippetManager.expandSnippets(in: corrected)
        let trimmed = withSnippets.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ProcessResult(text: "", didRemove: false, wordsRemovedCount: 0)
        }
        
        let nsString = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = Self.removalRegex.matches(in: trimmed, options: [], range: fullRange)
        
        guard !matches.isEmpty else {
            let normalized = Self.normalizeText(trimmed)
            return ProcessResult(text: normalized, didRemove: false, wordsRemovedCount: 0)
        }
        
        // Split text into tokens and scan sequentially
        // We'll tokenize by whitespace, retaining words and punctuation
        var tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var wordsRemoved = 0
        
        var i = 0
        while i < tokens.count {
            // Check if tokens starting at i form a "no no no" (or "no no no remove") sequence
            if let matchLength = matchRemovalSequence(in: tokens, startingAt: i) {
                // Remove the trigger tokens
                tokens.removeSubrange(i..<(i + matchLength))
                
                // If there is a preceding word before index i, remove it
                if i > 0 {
                    tokens.remove(at: i - 1)
                    wordsRemoved += 1
                    i -= 1 // adjust index after removing preceding token
                }
            } else {
                i += 1
            }
        }
        
        let cleaned = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizeText(cleaned)
        return ProcessResult(text: normalized, didRemove: wordsRemoved > 0, wordsRemovedCount: wordsRemoved)
    }
    
    /// Helper to test if a sequence of tokens starting at index matches "no no no" (or "no no no remove").
    /// Returns the number of tokens consumed by the sequence (3 or 4 tokens).
    private func matchRemovalSequence(in tokens: [String], startingAt index: Int) -> Int? {
        guard index + 2 < tokens.count else { return nil }
        
        let t1 = cleanToken(tokens[index]).lowercased()
        let t2 = cleanToken(tokens[index + 1]).lowercased()
        let t3 = cleanToken(tokens[index + 2]).lowercased()
        
        guard t1 == "no" && t2 == "no" && t3 == "no" else { return nil }
        
        // If followed by "remove", consume all 4 tokens ("no no no remove")
        if index + 3 < tokens.count {
            let t4 = cleanToken(tokens[index + 3]).lowercased()
            if t4 == "remove" {
                return 4
            }
        }
        
        // Otherwise consume 3 tokens ("no no no")
        return 3
    }
    
    private func cleanToken(_ token: String) -> String {
        return token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }
    
    // MARK: - Smart Text Normalization
    
    /// Normalizes spoken punctuation, fixes orphan punctuation spacing, formats currencies/numbers,
    /// and ensures proper sentence capitalization.
    public static func normalizeText(_ input: String) -> String {
        var text = input
        guard !text.isEmpty else { return "" }
        
        // 1. Spoken Punctuation Normalization
        let punctuationReplacements: [(pattern: String, template: String)] = [
            (#"(?i)\b(?:full\s+stop|period)\b"#, "."),
            (#"(?i)\bquestion\s+mark\b"#, "?"),
            (#"(?i)\bexclamation\s+(?:mark|point)\b"#, "!"),
            (#"(?i)\bnew\s+line\b"#, "\n"),
            (#"(?i)\bnew\s+paragraph\b"#, "\n\n")
        ]
        for (pattern, template) in punctuationReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: (text as NSString).length)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
            }
        }
        
        // 2. Currency & Number Normalization
        let numberReplacements: [(pattern: String, template: String)] = [
            (#"(?i)\b(\d+)\s+dollars\b"#, "\\$$1"),
            (#"(?i)\b(\d+)\s+rupees\b"#, "₹$1"),
            (#"(?i)\b(\d+)\s+lakhs?\b"#, "$1 Lakh"),
            (#"(?i)\b(\d+)\s+crores?\b"#, "$1 Crore")
        ]
        for (pattern, template) in numberReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: (text as NSString).length)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
            }
        }
        
        // 3. Clean orphan spaces before punctuation: "hello , world" -> "hello, world"
        if let regex = try? NSRegularExpression(pattern: #"\s+([,.\?!:;])"#, options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
        }
        
        // 4. Clean orphan punctuation at beginning of text: ", hello" -> "hello"
        if let regex = try? NSRegularExpression(pattern: #"^[,.\?!:;]+\s*"#, options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // 5. Capitalize first letter of string
        text = capitalizeFirstLetter(text)
        
        // 6. Capitalize after sentence terminators (. ! ? \n)
        if let regex = try? NSRegularExpression(pattern: #"([.!?\n]\s+)([a-z])"#, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let charRange = match.range(at: 2)
                let charStr = nsText.substring(with: charRange)
                let upperStr = charStr.uppercased()
                text = (text as NSString).replacingCharacters(in: charRange, with: upperStr)
            }
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
