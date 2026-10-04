import Foundation
import Speech
import AVFoundation
import HardyFlowObjC

/// Manages native Apple Speech Recognition, multi-locale accent tuning (Indian English, Hindi, US, etc.),
/// real-time streaming partial results, and inline voice command mistake correction.
public final class SpeechRecognitionService: @unchecked Sendable {
    public static let shared = SpeechRecognitionService()
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let recognitionQueue = DispatchQueue(label: "com.hardyflow.speech", qos: .userInteractive)
    private static let queueKey = DispatchSpecificKey<Void>()
    private let commandProcessor = VoiceCommandProcessor()
    
    public private(set) var isRecognizing: Bool = false
    public private(set) var currentLocale: Locale
    
    /// Published callback with live cleaned transcription string and whether a removal just occurred.
    public var onTranscriptionUpdate: ((_ text: String, _ didRemoveWord: Bool) -> Void)?
    
    /// Published callback when final transcription is finalized.
    public var onFinalTranscription: ((_ text: String) -> Void)?
    
    /// Published callback when an error occurs during speech recognition.
    public var onError: ((Error) -> Void)?
    
    private var lastSpokenText: String = ""
    
    public init(locale: Locale = Locale(identifier: "en-IN")) {
        recognitionQueue.setSpecific(key: Self.queueKey, value: ())
        self.currentLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    private func performOnQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return try block()
        } else {
            return try recognitionQueue.sync(execute: block)
        }
    }
    
    /// Dynamically switches the active speech recognition locale (e.g. en-IN, hi-IN, en-US).
    public func setLocale(_ locale: Locale) {
        performOnQueue {
            self.currentLocale = locale
            self.speechRecognizer = SFSpeechRecognizer(locale: locale)
            print("🌐 [SpeechRecognitionService] Switched speech locale to: \(locale.identifier) (\(locale.localizedString(forIdentifier: locale.identifier) ?? ""))")
        }
    }
    
    /// Returns the comprehensive list of all locales supported by macOS Speech Recognition,
    /// sorted with Indian and popular English locales prioritized.
    public static var availableLocales: [Locale] {
        let locales = SFSpeechRecognizer.supportedLocales()
        
        let priorityOrder = ["en-IN", "hi-IN", "en-US", "en-GB", "en-CA", "en-AU"]
        
        return locales.sorted { (l1, l2) -> Bool in
            let id1 = l1.identifier
            let id2 = l2.identifier
            
            let p1 = priorityOrder.firstIndex(of: id1) ?? Int.max
            let p2 = priorityOrder.firstIndex(of: id2) ?? Int.max
            
            if p1 != p2 {
                return p1 < p2
            }
            return id1 < id2
        }
    }
    
    /// Checks or requests system Speech Recognition authorization.
    public static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("✅ [SpeechRecognitionService] Speech recognition authorized.")
                    completion(true)
                case .denied, .restricted, .notDetermined:
                    print("⚠️ [SpeechRecognitionService] Speech recognition authorization status: \(status.rawValue)")
                    completion(false)
                @unknown default:
                    completion(false)
                }
            }
        }
    }
    
    public static var isAuthorized: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Starts a streaming recognition session.
    /// Starts a streaming recognition session.
    public func startSession() throws {
        try performOnQueue {
            if isRecognizing {
                cancelSessionInternal()
            }
            try startSessionInternal()
        }
    }
    
    /// Resets the active speech recognizer session so subsequent speech starts from an empty buffer.
    /// Does not halt the microphone engine; subsequent audio buffers stream into a fresh request with zero old words.
    public func resetSessionForFreshInput() {
        performOnQueue {
            guard isRecognizing else { return }
            cancelSessionInternal()
            do {
                try startSessionInternal()
                print("🔄 [SpeechRecognitionService] Speech recognition session restarted with clean acoustic buffer.")
            } catch {
                print("⚠️ [SpeechRecognitionService] Failed to restart fresh recognition session: \(error)")
            }
        }
    }
    
    private func startSessionInternal() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "HardyFlowSpeechError",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available for locale \(currentLocale.identifier)."]
            )
        }
        
        lastSpokenText = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        
        // Allow Apple's cloud neural models for maximum accuracy when connected, falling back to on-device
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        
        // Prime acoustic model with comprehensive tech and Indian vocabulary
        request.contextualStrings = CustomVocabulary.allContextualStrings
        
        self.recognitionRequest = request
        
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let result = result {
                let rawText = result.bestTranscription.formattedString
                let processed = self.commandProcessor.process(rawText)
                
                if processed.didRemove {
                    SoundManager.shared.playWordRemovedCue()
                }
                
                self.lastSpokenText = processed.text
                
                DispatchQueue.main.async {
                    self.onTranscriptionUpdate?(processed.text, processed.didRemove)
                }
                
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onFinalTranscription?(processed.text)
                    }
                }
            }
            
            if let error = error {
                // Ignore normal cancellation errors (code 216 / 203)
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 203) {
                    return
                }
                print("⚠️ [SpeechRecognitionService] Task error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }
        
        isRecognizing = true
        print("🚀 [SpeechRecognitionService] Recognition session started for \(currentLocale.identifier).")
    }
    
    private func cancelSessionInternal() {
        isRecognizing = false
        var error: NSError?
        HardyFlowTryCatch({
            self.recognitionTask?.cancel()
            self.recognitionRequest?.endAudio()
        }, &error)
        self.recognitionTask = nil
        self.recognitionRequest = nil
        self.lastSpokenText = ""
    }
    
    /// Feeds an incoming PCM buffer into the active recognition request.
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionQueue.async { [weak self] in
            guard let self = self, self.isRecognizing, let request = self.recognitionRequest else { return }
            var error: NSError?
            HardyFlowTryCatch({
                request.append(buffer)
            }, &error)
            if let error = error {
                print("⚠️ [SpeechRecognitionService] Buffer append notice: \(error.localizedDescription)")
            }
        }
    }
    
    /// Finishes the current audio stream and awaits final transcription result.
    public func finishSession() {
        performOnQueue {
            guard isRecognizing else { return }
            isRecognizing = false
            var error: NSError?
            HardyFlowTryCatch({
                self.recognitionRequest?.endAudio()
            }, &error)
            print("🏁 [SpeechRecognitionService] Recognition session ended audio.")
        }
    }
    
    /// Immediately cancels the recognition task.
    public func cancelSession() {
        performOnQueue {
            cancelSessionInternal()
            print("🛑 [SpeechRecognitionService] Recognition session cancelled.")
        }
    }
}
