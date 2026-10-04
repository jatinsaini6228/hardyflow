import Foundation
import Combine
import SwiftUI
import Speech
import AVFAudio
import AVFoundation
import AppKit

/// Primary reactive state store for HardyFlow, orchestrating audio capture, speech recognition,
/// wake-word listening, silence detection, and background paste delivery.
public final class AppState: ObservableObject, @unchecked Sendable {
    public static let shared = AppState()
    
    public enum RecordingStatus: Equatable, Sendable {
        case idle
        case listeningWakeWord
        case recording
        case finishing
    }
    
    // MARK: - Published Reactive State
    @Published public var status: RecordingStatus = .idle
    @Published public var transcribedText: String = ""
    @Published public var audioLevel: Float = 0.0
    @Published public var didRecentlyRemoveWord: Bool = false
    @Published public var selectedLocale: Locale
    @Published public var isWakeWordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWakeWordEnabled, forKey: "HardyFlow_WakeWordEnabled")
            handleWakeWordSettingChanged()
        }
    }
    @Published public var isAutoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoPasteEnabled, forKey: "HardyFlow_AutoPasteEnabled")
        }
    }
    @Published public var isSoundEffectsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEffectsEnabled, forKey: "HardyFlow_SoundEffectsEnabled")
            SoundManager.shared.isSoundEnabled = isSoundEffectsEnabled
        }
    }
    @Published public var silenceTimeout: Double {
        didSet {
            UserDefaults.standard.set(silenceTimeout, forKey: "HardyFlow_SilenceTimeout")
        }
    }
    
    // UI View State (managed here to ensure clean Swift 6 compilation without Xcode SwiftUIMacros)
    @Published public var selectedPreferencesTab: Int = 0
    @Published public var isMicAuthorized: Bool = false
    @Published public var isSpeechAuthorized: Bool = false
    @Published public var isAccessibilityAuthorized: Bool = false
    @Published public var isChipHovered: Bool = false
    @Published public var isWarningDismissed: Bool = false
    
    // Recent transcripts history for quick reference
    @Published public var recentTranscriptions: [String] = []
    
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.05
    private var isTriggeredByWakeWord: Bool = false
    
    private init() {
        // Restore user defaults with backwards compatibility
        let savedLocaleId = UserDefaults.standard.string(forKey: "HardyFlow_Locale")
            ?? UserDefaults.standard.string(forKey: "Wisperflow_Locale")
            ?? "en-IN"
        self.selectedLocale = Locale(identifier: savedLocaleId)
        
        let savedWakeWord = UserDefaults.standard.object(forKey: "HardyFlow_WakeWordEnabled") as? Bool
            ?? UserDefaults.standard.bool(forKey: "Wisperflow_WakeWordEnabled")
        self.isWakeWordEnabled = savedWakeWord
        
        let savedAutoPaste = UserDefaults.standard.object(forKey: "HardyFlow_AutoPasteEnabled") as? Bool
            ?? UserDefaults.standard.object(forKey: "Wisperflow_AutoPasteEnabled") as? Bool
            ?? true
        self.isAutoPasteEnabled = savedAutoPaste
        
        let savedSounds = UserDefaults.standard.object(forKey: "HardyFlow_SoundEffectsEnabled") as? Bool
            ?? UserDefaults.standard.object(forKey: "Wisperflow_SoundEffectsEnabled") as? Bool
            ?? true
        self.isSoundEffectsEnabled = savedSounds
        SoundManager.shared.isSoundEnabled = savedSounds
        
        let savedTimeout = UserDefaults.standard.object(forKey: "HardyFlow_SilenceTimeout") as? Double
            ?? UserDefaults.standard.double(forKey: "Wisperflow_SilenceTimeout")
        self.silenceTimeout = savedTimeout > 0 ? savedTimeout : 1.8
        
        setupSubsystems()
        refreshPermissions()
        startPermissionMonitoring()
        setupActivationObservers()
    }
    
    private func setupSubsystems() {
        // Bind audio level
        AudioEngineManager.shared.onAudioLevelChanged = { [weak self] level in
            guard let self = self else { return }
            self.audioLevel = level
            self.handleAudioLevelForSilence(level)
        }
        
        // Route audio buffers
        AudioEngineManager.shared.onAudioBuffer = { [weak self] buffer in
            guard let self = self else { return }
            if self.status == .recording {
                SpeechRecognitionService.shared.appendAudioBuffer(buffer)
            } else if self.status == .listeningWakeWord {
                WakeWordDetector.shared.appendAudioBuffer(buffer)
            }
        }
        
        // Bind speech updates
        SpeechRecognitionService.shared.onTranscriptionUpdate = { [weak self] text, didRemove in
            guard let self = self else { return }
            self.transcribedText = text
            if didRemove {
                self.didRecentlyRemoveWord = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.didRecentlyRemoveWord = false
                }
            }
            // Reset silence timer on new spoken text
            self.resetSilenceTimer()
        }
        
        SpeechRecognitionService.shared.onFinalTranscription = { [weak self] text in
            guard let self = self else { return }
            if !text.isEmpty {
                self.recordTranscript(text)
            }
        }
        
        // Bind Wake Word trigger
        WakeWordDetector.shared.onWakeWordDetected = { [weak self] in
            guard let self = self else { return }
            print("🎙️ [AppState] Wake word triggered! Transitioning to active recording.")
            self.isTriggeredByWakeWord = true
            self.startRecording()
        }
        
        // Initial wake word check
        if isWakeWordEnabled {
            startWakeWordListening()
        }
    }
    
    // MARK: - Actions
    
    public func toggleRecording() {
        if status == .recording {
            stopRecordingAndDeliver()
        } else {
            isTriggeredByWakeWord = false
            startRecording()
        }
    }
    
    public func startRecording() {
        guard status != .recording else { return }
        
        // 1. Verify Microphone Access via modern AVAudioApplication API
        let micPerm = AVAudioApplication.shared.recordPermission
        if micPerm == .undetermined {
            NSApp.activate(ignoringOtherApps: true)
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.refreshPermissions()
                    if granted {
                        self?.startRecording()
                    } else {
                        SoundManager.shared.playErrorCue()
                        Self.openMicrophoneSettings()
                    }
                }
            }
            return
        } else if micPerm == .denied {
            SoundManager.shared.playErrorCue()
            Self.openMicrophoneSettings()
            return
        }
        
        // 2. Verify Speech Recognition Access
        if !SpeechRecognitionService.isAuthorized {
            NSApp.activate(ignoringOtherApps: true)
            SpeechRecognitionService.requestAuthorization { [weak self] authorized in
                DispatchQueue.main.async {
                    self?.refreshPermissions()
                    if authorized {
                        self?.startRecording()
                    } else {
                        SoundManager.shared.playErrorCue()
                        Self.openSpeechSettings()
                    }
                }
            }
            return
        }
        
        // Capture frontmost application prior to presenting HUD
        PasteService.shared.recordCurrentFrontmostApp()
        
        // Stop wake word detector while dictating
        WakeWordDetector.shared.stopListening()
        
        transcribedText = ""
        status = .recording
        SoundManager.shared.playStartCue()
        
        do {
            SpeechRecognitionService.shared.setLocale(selectedLocale)
            try SpeechRecognitionService.shared.startSession()
            try AudioEngineManager.shared.start()
            resetSilenceTimer()
        } catch {
            print("❌ [AppState] Failed to start dictation: \(error)")
            SoundManager.shared.playErrorCue()
            status = .idle
            restartWakeWordIfNeeded()
        }
    }
    
    public func stopRecordingAndDeliver() {
        guard status == .recording else { return }
        status = .finishing
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        SoundManager.shared.playStopCue()
        SpeechRecognitionService.shared.finishSession()
        AudioEngineManager.shared.stop()
        
        let textToDeliver = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !textToDeliver.isEmpty {
            recordTranscript(textToDeliver)
        }
        
        if isAutoPasteEnabled && !textToDeliver.isEmpty {
            PasteService.shared.pasteDirectly(text: textToDeliver) { [weak self] in
                DispatchQueue.main.async {
                    self?.status = .idle
                    self?.restartWakeWordIfNeeded()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.status = .idle
                self?.restartWakeWordIfNeeded()
            }
        }
    }
    
    public func cancelRecording() {
        guard status == .recording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        SpeechRecognitionService.shared.cancelSession()
        AudioEngineManager.shared.stop()
        transcribedText = ""
        status = .idle
        restartWakeWordIfNeeded()
    }
    
    /// Completely stops all recording, wake word detection, and audio engine processing.
    public func stopListeningCompletely() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        SpeechRecognitionService.shared.cancelSession()
        WakeWordDetector.shared.stopListening()
        AudioEngineManager.shared.stop()
        status = .idle
        print("⏹️ [AppState] Stopped all listening and audio engine completely.")
    }
    
    /// Purges all transcribed text, recent history, and in-memory temporary audio buffers.
    /// Guarantees zero residual audio or session artifacts remain in memory.
    public func purgeAllSessionData() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        transcribedText = ""
        recentTranscriptions.removeAll()
        AudioEngineManager.shared.purgeTemporaryAudioMemory()
        print("🧹 [AppState] All session data and temporary audio memory purged.")
    }
    
    public func setLocale(_ locale: Locale) {
        self.selectedLocale = locale
        UserDefaults.standard.set(locale.identifier, forKey: "HardyFlow_Locale")
        SpeechRecognitionService.shared.setLocale(locale)
    }
    
    private func handleWakeWordSettingChanged() {
        if isWakeWordEnabled {
            startWakeWordListening()
        } else {
            WakeWordDetector.shared.stopListening()
            if status == .listeningWakeWord {
                AudioEngineManager.shared.stop()
                status = .idle
            }
        }
    }
    
    private func startWakeWordListening() {
        guard status == .idle else { return }
        
        let micPerm = AVAudioApplication.shared.recordPermission
        guard micPerm == .granted && SpeechRecognitionService.isAuthorized else {
            print("⚠️ [AppState] Cannot start wake-word listening: Microphone or Speech permission not yet granted.")
            return
        }
        
        status = .listeningWakeWord
        WakeWordDetector.shared.startListening()
        do {
            try AudioEngineManager.shared.start()
        } catch {
            print("⚠️ [AppState] Failed to start audio engine for wake word: \(error)")
            status = .idle
        }
    }
    
    private func restartWakeWordIfNeeded() {
        if isWakeWordEnabled {
            startWakeWordListening()
        }
    }
    
    private func handleAudioLevelForSilence(_ level: Float) {
        guard status == .recording else { return }
        
        // If sound is actively detected above threshold, reset timer
        if level > silenceThreshold {
            resetSilenceTimer()
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        guard status == .recording else { return }
        
        // Only auto-stop if text has actually been spoken
        let hasSpoken = !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSpoken else { return }
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.status == .recording else { return }
            print("🤫 [AppState] Silence detected for \(self.silenceTimeout)s. Concluding dictation.")
            self.stopRecordingAndDeliver()
        }
    }
    
    private func recordTranscript(_ text: String) {
        if !recentTranscriptions.contains(text) {
            recentTranscriptions.insert(text, at: 0)
            if recentTranscriptions.count > 10 {
                recentTranscriptions.removeLast()
            }
        }
    }
    
    private var permissionPollTimer: Timer?
    
    /// Starts background polling to detect when users grant permissions in System Settings in real time.
    public func startPermissionMonitoring() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }
    
    private func setupActivationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissions()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissions()
        }
    }
    
    public func refreshPermissions() {
        let micAv = (AVAudioApplication.shared.recordPermission == .granted)
        let micCapture = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        let mic = micAv || micCapture
        let speech = SpeechRecognitionService.isAuthorized
        let ax = PasteService.isAccessibilityTrusted
        
        DispatchQueue.main.async {
            if self.isMicAuthorized != mic {
                self.isMicAuthorized = mic
                print("🎙️ [AppState] Mic permission updated: \(mic)")
            }
            if self.isSpeechAuthorized != speech {
                self.isSpeechAuthorized = speech
                print("🗣️ [AppState] Speech permission updated: \(speech)")
            }
            if self.isAccessibilityAuthorized != ax {
                self.isAccessibilityAuthorized = ax
                print("♿ [AppState] Accessibility permission updated: \(ax)")
            }
        }
    }
    
    public func requestMicrophoneAccess() {
        let perm = AVAudioApplication.shared.recordPermission
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if perm == .denied || captureStatus == .denied {
            Self.openMicrophoneSettings()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicAuthorized = granted
                    self?.refreshPermissions()
                }
            }
        }
    }
    
    public func requestSpeechAccess() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .denied || status == .restricted {
            Self.openSpeechSettings()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            SpeechRecognitionService.requestAuthorization { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isSpeechAuthorized = granted
                    self?.refreshPermissions()
                }
            }
        }
    }
    
    public func requestAccessibilityAccess() {
        PasteService.requestAccessibilityPermissions()
        PasteService.openAccessibilitySettings()
        refreshPermissions()
    }
    
    public static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public static func openSpeechSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public static func openAccessibilitySettings() {
        PasteService.openAccessibilitySettings()
    }
}
