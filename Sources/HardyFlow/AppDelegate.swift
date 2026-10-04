import Foundation
import AppKit
import AVFoundation
import Speech
import HardyFlowCore
import HardyFlowUI

/// Main application delegate coordinating startup lifecycle, hotkey registration, and menu bar presentation.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎙️ [HardyFlow] Application launching...")
        
        // Ensure menu bar accessory status (no Dock icon, unobtrusive)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup observer for preference requests
        let prefObserver: (Notification) -> Void = { _ in
            PreferencesWindowController.shared.showWindow()
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HardyFlowOpenPreferences"),
            object: nil,
            queue: .main,
            using: prefObserver
        )
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WisperflowOpenPreferences"),
            object: nil,
            queue: .main,
            using: prefObserver
        )
        
        // Initialize subsystems
        _ = AppState.shared
        _ = FloatingHUDWindowController.shared
        _ = StatusBarController.shared
        
        // Setup global hotkey (Option + Space)
        setupGlobalHotkey()
        
        // Verify permissions on initial launch
        verifyInitialPermissions()
        
        print("✨ [HardyFlow] Ready for speech-to-text dictation across all apps (⌥ Space).")
    }
    
    private func setupGlobalHotkey() {
        HotkeyManager.shared.registerDefaultHotkey()
        HotkeyManager.shared.onHotkeyPressed = {
            print("⚡ [HardyFlow] Global hotkey pressed (⌥ Space) -> toggling dictation.")
            AppState.shared.toggleRecording()
        }
    }
    
    private func verifyInitialPermissions() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let isAccessibility = PasteService.isAccessibilityTrusted
        
        // If critical permissions have never been prompted, launch Preferences window and request access
        if micStatus == .notDetermined || speechStatus == .notDetermined || !isAccessibility {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                PreferencesWindowController.shared.showWindow()
                
                if micStatus == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async {
                            AppState.shared.refreshPermissions()
                        }
                    }
                }
                
                if speechStatus == .notDetermined {
                    SpeechRecognitionService.requestAuthorization { _ in
                        DispatchQueue.main.async {
                            AppState.shared.refreshPermissions()
                        }
                    }
                }
                
                if !isAccessibility {
                    PasteService.requestAccessibilityPermissions()
                }
            }
        }
        
        AppState.shared.refreshPermissions()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
        WakeWordDetector.shared.stopListening()
        AudioEngineManager.shared.purgeTemporaryAudioMemory()
        AppState.shared.purgeAllSessionData()
        print("🛑 [HardyFlow] Application terminated. All temporary audio memory and session data purged.")
    }
}
