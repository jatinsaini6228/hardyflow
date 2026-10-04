import Foundation
import AppKit
import Carbon

/// Coordinates target application tracking, focus restoration, system clipboard updates,
/// and direct synthetic Command + V paste dispatch into background applications.
public final class PasteService: NSObject, @unchecked Sendable {
    public static let shared = PasteService()
    
    /// Tracks the external application that had focus prior to HardyFlow activation.
    public private(set) var previousFrontmostApp: NSRunningApplication?
    
    /// Last detected external active application.
    public private(set) var lastActiveExternalApp: NSRunningApplication?
    
    private override init() {
        super.init()
        startTrackingActiveApplications()
    }
    
    private func startTrackingActiveApplications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        if let current = NSWorkspace.shared.frontmostApplication, isExternalApp(current) {
            lastActiveExternalApp = current
            previousFrontmostApp = current
        }
    }
    
    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if isExternalApp(app) {
            lastActiveExternalApp = app
            previousFrontmostApp = app
        }
    }
    
    /// Captures the current frontmost external application at the start of a dictation session.
    public func recordCurrentFrontmostApp() {
        if let current = NSWorkspace.shared.frontmostApplication, isExternalApp(current) {
            previousFrontmostApp = current
            lastActiveExternalApp = current
        }
    }
    
    public func isExternalApp(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else { return false }
        if let bundleId = app.bundleIdentifier, let myBundleId = Bundle.main.bundleIdentifier, bundleId == myBundleId {
            return false
        }
        if app.processIdentifier == NSRunningApplication.current.processIdentifier {
            return false
        }
        return true
    }
    
    /// Resolves the most appropriate external application to receive the pasted text.
    public var targetApplication: NSRunningApplication? {
        if let app = previousFrontmostApp, isExternalApp(app) {
            return app
        }
        if let app = lastActiveExternalApp, isExternalApp(app) {
            return app
        }
        return NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && self.isExternalApp($0)
        })
    }
    
    /// Copies text to clipboard and synthesizes Command + V in the background application.
    public func pasteDirectly(text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }
        
        // 1. Copy to system pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 2. Hide HUD and yield focus immediately so the background application can take focus
        NotificationCenter.default.post(name: NSNotification.Name("HardyFlowHideHUD"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("WisperflowHideHUD"), object: nil)
        NSApp.deactivate()
        
        let target = self.targetApplication
        
        // 3. Reactivate the target application and dispatch paste
        if let targetApp = target {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: targetApp)
                targetApp.activate()
            } else {
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }
            
            // Allow macOS window server 250ms to switch focus to target application
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.simulatePasteKeystroke(for: targetApp)
                completion?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.simulatePasteKeystroke(for: nil)
                completion?()
            }
        }
    }
    
    /// Synthesizes Command + V using Quartz CGEvent with 45ms hold duration and AppleScript fallback.
    public func simulatePasteKeystroke(for targetApp: NSRunningApplication? = nil) {
        if Self.isAccessibilityTrusted {
            let vKeyCode: CGKeyCode = 0x09 // ANSI 'V'
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            
            // 1. Post key down to session and directly to target pid if available
            keyDown.post(tap: .cgSessionEventTap)
            if let pid = targetApp?.processIdentifier {
                keyDown.postToPid(pid)
            }
            
            // 2. Hold key down for 45ms before key up so all macOS apps (Chrome, Notes, Slack, VS Code) register it!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                keyUp.post(tap: .cgSessionEventTap)
                if let pid = targetApp?.processIdentifier {
                    keyUp.postToPid(pid)
                }
                print("⌨️ [PasteService] CGEvent Cmd+V dispatched successfully (KeyDown + KeyUp 45ms hold).")
            }
            return
        }
        
        // If Accessibility is not yet granted, trigger prompt and attempt AppleScript fallback
        print("⚠️ [PasteService] Accessibility not granted; requesting permission and trying AppleScript fallback.")
        Self.requestAccessibilityPermissions()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource: String
            if let app = targetApp, !app.isTerminated {
                let pid = app.processIdentifier
                scriptSource = """
                tell application "System Events"
                    try
                        set frontmost of (first process whose unix id is \(pid)) to true
                    end try
                    delay 0.05
                    keystroke "v" using command down
                end tell
                """
            } else {
                scriptSource = """
                tell application "System Events"
                    delay 0.05
                    keystroke "v" using command down
                end tell
                """
            }
            
            if let script = NSAppleScript(source: scriptSource) {
                var errorInfo: NSDictionary?
                script.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    print("⚠️ [PasteService] AppleScript paste notice: \(err)")
                } else {
                    print("⌨️ [PasteService] AppleScript Cmd+V dispatched successfully.")
                }
            }
        }
    }
    
    /// Verifies if the app has macOS Accessibility permissions.
    public static var isAccessibilityTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Requests macOS Accessibility permissions with a system modal prompt.
    public static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Deep-links directly to System Settings -> Privacy & Security -> Accessibility.
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
