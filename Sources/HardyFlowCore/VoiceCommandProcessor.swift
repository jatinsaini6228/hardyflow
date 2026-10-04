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
    
    /// Processes a raw transcription string, removes any "NO NO NO" trigger sequences,
    /// and backtracks to remove the preceding word for each detected command.
    public func process(_ rawText: String) -> ProcessResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ProcessResult(text: "", didRemove: false, wordsRemovedCount: 0)
        }
        
        let nsString = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = Self.removalRegex.matches(in: trimmed, options: [], range: fullRange)
        
        guard !matches.isEmpty else {
            return ProcessResult(text: trimmed, didRemove: false, wordsRemovedCount: 0)
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
        return ProcessResult(text: cleaned, didRemove: wordsRemoved > 0, wordsRemovedCount: wordsRemoved)
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
}
