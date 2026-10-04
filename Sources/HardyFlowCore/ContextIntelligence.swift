import Foundation
import AppKit

/// Intelligently detects the frontmost application context (email client, code editor, terminal, or chat)
/// to automatically select optimal AI Polish tags and formatting modes (Phase 2 intelligence).
public enum ContextIntelligence {
    
    public enum AppCategory: Equatable, Sendable {
        case email
        case developer
        case chat
        case general
    }
    
    /// Analyzes an application and categorizes its primary interaction model.
    public static func categorizeApp(_ app: NSRunningApplication?) -> AppCategory {
        guard let app = app else { return .general }
        let bundleId = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        
        // 1. Email Applications
        if bundleId.contains("mail") ||
           bundleId.contains("outlook") ||
           bundleId.contains("spark") ||
           bundleId.contains("airmail") ||
           bundleId.contains("thunderbird") ||
           bundleId.contains("canary") ||
           name.contains("mail") ||
           name.contains("outlook") ||
           name.contains("spark") {
            return .email
        }
        
        // 2. Developer, Code Editors, Terminals & IDEs
        if bundleId.contains("vscode") ||
           bundleId.contains("cursor") ||
           bundleId.contains("xcode") ||
           bundleId.contains("terminal") ||
           bundleId.contains("iterm") ||
           bundleId.contains("warp") ||
           bundleId.contains("sublime") ||
           bundleId.contains("jetbrains") ||
           bundleId.contains("githubclient") ||
           name.contains("code") ||
           name.contains("cursor") ||
           name.contains("xcode") ||
           name.contains("terminal") ||
           name.contains("iterm") ||
           name.contains("warp") ||
           name.contains("intellij") ||
           name.contains("pycharm") ||
           name.contains("webstorm") ||
           name.contains("android studio") {
            return .developer
        }
        
        // 3. Chat & Messaging Applications
        if bundleId.contains("slack") ||
           bundleId.contains("discord") ||
           bundleId.contains("whatsapp") ||
           bundleId.contains("telegram") ||
           bundleId.contains("teams") ||
           bundleId.contains("signal") ||
           bundleId.contains("messages") ||
           name.contains("slack") ||
           name.contains("discord") ||
           name.contains("whatsapp") ||
           name.contains("telegram") ||
           name.contains("teams") ||
           name.contains("messages") {
            return .chat
        }
        
        return .general
    }
    
    /// Suggests the best AI Polish Tag based on the active application.
    public static func suggestedTag(for app: NSRunningApplication?) -> PolishTag {
        switch categorizeApp(app) {
        case .email:
            return .email
        case .developer:
            return .aiPrompt
        case .chat, .general:
            return .noTag
        }
    }
    
    /// Returns a short label indicating the active application context for display in the HUD.
    public static func contextDisplayTitle(for app: NSRunningApplication?) -> String? {
        guard let app = app, let name = app.localizedName, !name.isEmpty else { return nil }
        return name
    }
}
