import Foundation

/// Manages voice-triggered text macros and snippet expansions (Phase 4 productivity power-tools).
public enum SnippetManager {
    
    public static var userEmail: String {
        get { UserDefaults.standard.string(forKey: "HardyFlow_Snippet_Email") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "HardyFlow_Snippet_Email") }
    }
    
    public static var userPhone: String {
        get { UserDefaults.standard.string(forKey: "HardyFlow_Snippet_Phone") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "HardyFlow_Snippet_Phone") }
    }
    
    public static var userMeeting: String {
        get { UserDefaults.standard.string(forKey: "HardyFlow_Snippet_Meeting") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "HardyFlow_Snippet_Meeting") }
    }
    
    public static let bugTemplate: String = """
    ### Bug Report
    - **Observed:** 
    - **Expected:** 
    - **Steps to Reproduce:** 
    """
    
    public static let prTemplate: String = """
    ### Summary of Changes
    - 
    ### Testing & Verification
    - 
    """
    
    /// Expands spoken macro triggers into formatted text.
    public static func expandSnippets(in text: String) -> String {
        var result = text
        
        // 1. Bug Template Macro
        let bugPattern = #"(?i)\b(?:insert\s+)?bug\s+template\b"#
        if let regex = try? NSRegularExpression(pattern: bugPattern, options: []) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: bugTemplate)
        }
        
        // 2. PR Template Macro
        let prPattern = #"(?i)\b(?:insert\s+)?(?:pr|pull\s+request)\s+template\b"#
        if let regex = try? NSRegularExpression(pattern: prPattern, options: []) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: prTemplate)
        }
        
        // 3. User Email Macro (if configured)
        let email = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            let emailPattern = #"(?i)\b(?:insert\s+)?my\s+email\b"#
            if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: email)
            }
        }
        
        // 4. User Phone Macro (if configured)
        let phone = userPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty {
            let phonePattern = #"(?i)\b(?:insert\s+)?my\s+phone(?:\s+number)?\b"#
            if let regex = try? NSRegularExpression(pattern: phonePattern, options: []) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: phone)
            }
        }
        
        // 5. User Meeting Link Macro (if configured)
        let meeting = userMeeting.trimmingCharacters(in: .whitespacesAndNewlines)
        if !meeting.isEmpty {
            let meetingPattern = #"(?i)\b(?:insert\s+)?my\s+(?:meeting|meet)(?:\s+link)?\b"#
            if let regex = try? NSRegularExpression(pattern: meetingPattern, options: []) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: meeting)
            }
        }
        
        return result
    }
}
