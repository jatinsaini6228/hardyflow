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
    
    // AI Enhancement & Polish State
    @Published public var isListeningPaused: Bool = false
    @Published public var selectedAITag: PolishTag = .noTag
    @Published public var isPolishing: Bool = false
    @Published public var prePolishText: String? = nil
    @Published public var isAIAvailable: Bool = false
    @Published public var aiErrorMessage: String? = nil
    public private(set) var aiConfiguration: AIConfiguration?
    
    // Recent transcripts history for quick reference
    @Published public var recentTranscriptions: [String] = []
    
    // Per-App Context Intelligence (Phase 2)
    @Published public var isAppAwareContextEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAppAwareContextEnabled, forKey: "HardyFlow_AppAwareContextEnabled")
        }
    }
    @Published public var detectedAppContextTitle: String? = nil
    
    // Whisper Mode (Phase 4): Digital pre-gain boost for soft whispering
    @Published public var isWhisperModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWhisperModeEnabled, forKey: "HardyFlow_WhisperModeEnabled")
            AudioEngineManager.shared.isWhisperModeEnabled = isWhisperModeEnabled
        }
    }
    
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.05
    private var isTriggeredByWakeWord: Bool = false
    private var baseCommittedText: String = ""
    /// Guards against the custom TextEditor binding triggering handleUserManualTextEdit
    /// when speech recognition programmatically sets transcribedText.
    public var isProgrammaticTextUpdate: Bool = false
    
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
        
        let savedAppAware = UserDefaults.standard.object(forKey: "HardyFlow_AppAwareContextEnabled") as? Bool ?? true
        self.isAppAwareContextEnabled = savedAppAware
        
        let savedWhisper = UserDefaults.standard.bool(forKey: "HardyFlow_WhisperModeEnabled")
        self.isWhisperModeEnabled = savedWhisper
        AudioEngineManager.shared.isWhisperModeEnabled = savedWhisper
        
        setupSubsystems()
        reloadAIConfiguration()
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
            if self.status == .recording && !self.isListeningPaused {
                SpeechRecognitionService.shared.appendAudioBuffer(buffer)
            } else if self.status == .listeningWakeWord {
                WakeWordDetector.shared.appendAudioBuffer(buffer)
            }
        }
        
        // Bind speech updates
        SpeechRecognitionService.shared.onTranscriptionUpdate = { [weak self] liveSegment, didRemove in
            guard let self = self, !self.isListeningPaused else { return }
            
            let combined: String
            if self.baseCommittedText.isEmpty {
                combined = liveSegment
            } else if liveSegment.isEmpty {
                combined = self.baseCommittedText
            } else {
                combined = "\(self.baseCommittedText) \(liveSegment)"
            }
            
            self.isProgrammaticTextUpdate = true
            self.transcribedText = combined
            self.isProgrammaticTextUpdate = false
            if didRemove {
                self.didRecentlyRemoveWord = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self?.didRecentlyRemoveWord = false
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
        
        // Initialize wake word recognizer locale to match user preference
        WakeWordDetector.shared.setLocale(selectedLocale)
        
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
        if status == .recording || isListeningPaused {
            stopRecordingAndDeliver()
        } else {
            isTriggeredByWakeWord = false
            isListeningPaused = false
            startRecording()
        }
    }
    
    public func startRecording() {
        guard status != .recording else { return }
        isListeningPaused = false
        
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
        let targetApp = PasteService.shared.previousFrontmostApp
        self.detectedAppContextTitle = ContextIntelligence.contextDisplayTitle(for: targetApp)
        
        if isAppAwareContextEnabled {
            let suggestedTag = ContextIntelligence.suggestedTag(for: targetApp)
            self.selectedAITag = suggestedTag
            print("🎯 [AppState] App-Aware Context: frontmost app is '\(detectedAppContextTitle ?? "Unknown")', auto-selected tag: \(suggestedTag.displayName)")
        }
        
        // Stop wake word detector while dictating
        WakeWordDetector.shared.stopListening()
        
        baseCommittedText = ""
        isProgrammaticTextUpdate = true
        transcribedText = ""
        isProgrammaticTextUpdate = false
        status = .recording
        SoundManager.shared.playStartCue()
        
        do {
            SpeechRecognitionService.shared.setLocale(selectedLocale)
            try SpeechRecognitionService.shared.startSession()
            if !AudioEngineManager.shared.isRunning {
                try AudioEngineManager.shared.start()
            }
            resetSilenceTimer()
        } catch {
            print("❌ [AppState] Failed to start dictation: \(error)")
            SoundManager.shared.playErrorCue()
            status = .idle
            restartWakeWordIfNeeded()
        }
    }
    
    public func stopRecordingAndDeliver() {
        guard status == .recording || isListeningPaused else { return }
        isListeningPaused = false
        status = .finishing
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        SoundManager.shared.playStopCue()
        SpeechRecognitionService.shared.finishSession()
        
        // If wake word is NOT enabled, stop the audio engine to save battery.
        // If wake word IS enabled, keep the audio engine running for seamless wake-word listening!
        if !isWakeWordEnabled {
            AudioEngineManager.shared.stop()
        }
        
        let textToDeliver = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        baseCommittedText = ""
        
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
        guard status == .recording || isListeningPaused else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListeningPaused = false
        
        SpeechRecognitionService.shared.cancelSession()
        if !isWakeWordEnabled {
            AudioEngineManager.shared.stop()
        }
        baseCommittedText = ""
        transcribedText = ""
        status = .idle
        restartWakeWordIfNeeded()
    }
    
    /// Clears the active transcribed text and resets the speech recognizer acoustic buffer,
    /// guaranteeing that previously spoken words will never repeat when new speech begins.
    public func clearTranscribedText() {
        baseCommittedText = ""
        transcribedText = ""
        prePolishText = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if status == .recording {
            SpeechRecognitionService.shared.resetSessionForFreshInput()
            print("🧹 [AppState] Transcribed text cleared by user. Recognition session reset for fresh speech.")
        }
    }
    
    /// Handles manual editing inside the text box by the user, updating base committed text
    /// and restarting the recognition session so new speech appends cleanly without resurrecting deleted words.
    public func handleUserManualTextEdit(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcribedText = newText
        prePolishText = nil
        
        if trimmed.isEmpty {
            clearTranscribedText()
        } else {
            baseCommittedText = newText
            if status == .recording {
                SpeechRecognitionService.shared.resetSessionForFreshInput()
                print("✏️ [AppState] User manually edited text. Committed base text and restarted recognizer for subsequent speech.")
            }
        }
    }
    
    /// Instantly re-pastes the most recent transcription into the current external app (Option + Shift + V).
    public func rePasteLastTranscription() {
        guard let last = recentTranscriptions.first, !last.isEmpty else {
            print("⚠️ [AppState] Re-paste requested but recent transcripts history is empty.")
            SoundManager.shared.playErrorCue()
            return
        }
        print("📋 [AppState] Re-pasting last transcription (\(last.count) chars): \"\(last)\"")
        SoundManager.shared.playPasteCue()
        PasteService.shared.pasteDirectly(text: last)
    }
    
    /// Pauses listening without hiding the HUD popup card.
    /// Audio engine, microphone capture, and wake word are immediately terminated.
    public func pauseListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        SpeechRecognitionService.shared.finishSession()
        WakeWordDetector.shared.stopListening()
        AudioEngineManager.shared.stop()
        
        isListeningPaused = true
        audioLevel = 0.0
        print("⏸️ [AppState] Listening paused. HUD remains open for user review.")
    }
    
    /// Resumes active speech recording from paused state without wiping existing text.
    public func resumeListening() {
        guard isListeningPaused else { return }
        isListeningPaused = false
        
        // Verify permissions
        guard isMicAuthorized && isSpeechAuthorized else {
            refreshPermissions()
            return
        }
        
        status = .recording
        SoundManager.shared.playStartCue()
        
        do {
            SpeechRecognitionService.shared.setLocale(selectedLocale)
            try SpeechRecognitionService.shared.startSession()
            if !AudioEngineManager.shared.isRunning {
                try AudioEngineManager.shared.start()
            }
            resetSilenceTimer()
            print("▶️ [AppState] Resumed speech listening.")
        } catch {
            print("❌ [AppState] Failed to resume speech listening: \(error)")
            SoundManager.shared.playErrorCue()
            isListeningPaused = true
        }
    }
    
    /// Completely stops all recording, wake word detection, and audio engine processing.
    public func stopListeningCompletely() {
        pauseListening()
    }
    
    // MARK: - AI Enhancement & Polish
    
    public func reloadAIConfiguration() {
        if let config = EnvLoader.loadAIConfiguration() {
            self.aiConfiguration = config
            self.isAIAvailable = true
            print("🤖 [AppState] Local AI Llama 3 loaded: \(config.model) (\(config.apiUrl))")
        } else {
            self.isAIAvailable = false
            print("ℹ️ [AppState] No AI API key detected in .env.")
        }
    }
    
    public func polishCurrentText() {
        guard let config = aiConfiguration else {
            aiErrorMessage = "AI configuration missing. Check .env file."
            return
        }
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isPolishing = true
        aiErrorMessage = nil
        prePolishText = transcribedText
        
        Task {
            do {
                let polished = try await AIPolishService.shared.polish(
                    text: text,
                    tag: selectedAITag,
                    config: config
                )
                await MainActor.run {
                    self.isProgrammaticTextUpdate = true
                    self.transcribedText = polished
                    self.isProgrammaticTextUpdate = false
                    self.isPolishing = false
                    SoundManager.shared.playStartCue()
                    print("✨ [AppState] Successfully polished text with tag: \(self.selectedAITag.displayName)")
                }
            } catch {
                await MainActor.run {
                    self.isPolishing = false
                    self.aiErrorMessage = error.localizedDescription
                    SoundManager.shared.playErrorCue()
                    print("⚠️ [AppState] AI polish failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func undoPolish() {
        if let original = prePolishText {
            isProgrammaticTextUpdate = true
            transcribedText = original
            isProgrammaticTextUpdate = false
            prePolishText = nil
            SoundManager.shared.playWordRemovedCue()
            print("↺ [AppState] Reverted polish to original transcription.")
        }
    }
    
    /// Purges all transcribed text, recent history, and in-memory temporary audio buffers.
    /// Guarantees zero residual audio or session artifacts remain in memory.
    public func purgeAllSessionData() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        isProgrammaticTextUpdate = true
        transcribedText = ""
        isProgrammaticTextUpdate = false
        recentTranscriptions.removeAll()
        AudioEngineManager.shared.purgeTemporaryAudioMemory()
        print("🧹 [AppState] All session data and temporary audio memory purged.")
    }
    
    public func setLocale(_ locale: Locale) {
        self.selectedLocale = locale
        UserDefaults.standard.set(locale.identifier, forKey: "HardyFlow_Locale")
        SpeechRecognitionService.shared.setLocale(locale)
        WakeWordDetector.shared.setLocale(locale)
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
        if !AudioEngineManager.shared.isRunning {
            do {
                try AudioEngineManager.shared.start()
            } catch {
                print("⚠️ [AppState] Failed to start audio engine for wake word: \(error)")
                status = .idle
            }
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
            let previousCanListen = self.isMicAuthorized && self.isSpeechAuthorized
            
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
            
            let nowCanListen = mic && speech
            if !previousCanListen && nowCanListen && self.isWakeWordEnabled && self.status == .idle {
                print("🎙️ [AppState] Permissions confirmed. Starting wake word ambient listening.")
                self.startWakeWordListening()
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
