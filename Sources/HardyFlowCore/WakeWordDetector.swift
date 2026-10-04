import Foundation
import Speech
import AVFoundation
import HardyFlowObjC

/// Monitors continuous ambient background audio buffers specifically listening for "Hey Hardy", "Hi Hardy", and phonetic variants.
/// Seamlessly transitions the app into full dictation mode upon detection.
public final class WakeWordDetector: @unchecked Sendable {
    public static let shared = WakeWordDetector()
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let detectorQueue = DispatchQueue(label: "com.hardyflow.wakeword", qos: .userInitiated)
    private static let queueKey = DispatchSpecificKey<Void>()
    
    public private(set) var isListening: Bool = false
    public private(set) var currentLocale: Locale
    
    /// Callback triggered when the wake word is verified in the ambient audio stream.
    public var onWakeWordDetected: (() -> Void)?
    
    private let greetings: Set<String> = [
        "hey", "hi", "hello", "ok", "okay", "a", "the", "he", "hay"
    ]
    
    private let wakeTargetWords: Set<String> = [
        "hardy", "hardi", "hearty", "hardik", "harry", "harvey", "hardly", "party", "artie", "flow"
    ]
    
    /// Supported wake phrases for direct string and token matching.
    public let wakePhrases: [String] = [
        "hey hardy", "hi hardy", "ok hardy", "okay hardy", "hello hardy",
        "hey hardi", "hi hardi", "ok hardi", "okay hardi", "hello hardi",
        "hardy flow", "hardyflow",
        "hey hearty", "hi hearty", "ok hearty",
        "hey hardly", "hi hardly", "ok hardly",
        "hey harry", "hi harry", "hello harry",
        "hey harvey", "hi harvey",
        "hey hardik", "hi hardik",
        "hey party", "hi party",
        "hey wisper", "hey whisper", "hi wisper", "hi whisper"
    ]
    
    public init(locale: Locale = Locale(identifier: "en-IN")) {
        detectorQueue.setSpecific(key: Self.queueKey, value: ())
        self.currentLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    private func performOnQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return try block()
        } else {
            return try detectorQueue.sync(execute: block)
        }
    }
    
    /// Dynamically switches the wake word recognizer's locale to match the active user language.
    public func setLocale(_ locale: Locale) {
        performOnQueue {
            self.currentLocale = locale
            self.speechRecognizer = SFSpeechRecognizer(locale: locale)
            print("🌐 [WakeWordDetector] Updated wake word recognizer locale: \(locale.identifier)")
            if self.isListening {
                self.restartRecognitionTask()
            }
        }
    }
    
    /// Starts background ambient listening for "Hey Hardy" / "Hi Hardy".
    public func startListening() {
        performOnQueue {
            guard !isListening else { return }
            isListening = true
            startRecognitionTask()
            print("👂 [WakeWordDetector] Ambient wake word listener active ('Hey Hardy' / 'Hi Hardy').")
        }
    }
    
    private func startRecognitionTask() {
        guard isListening else { return }
        
        // Clean up previous task if any
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("⚠️ [WakeWordDetector] Speech recognizer unavailable for wake word.")
            return
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        request.contextualStrings = CustomVocabulary.wakeWordContextualStrings
        
        self.recognitionRequest = request
        
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let result = result {
                let raw = result.bestTranscription.formattedString
                if self.isWakePhraseDetected(in: raw) {
                    print("✨ [WakeWordDetector] Wake word triggered! Heard: '\(raw)'")
                    self.stopListeningInternal()
                    
                    DispatchQueue.main.async {
                        SoundManager.shared.playWakeWordCue()
                        self.onWakeWordDetected?()
                    }
                    return
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                // Ignore harmless cancellation codes (216 / 203)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 203) {
                    return
                }
                // Auto-recycle recognition task on timeout / 60-second limit to keep ambient listening alive
                if self.isListening {
                    self.detectorQueue.asyncAfter(deadline: .now() + 0.3) {
                        guard self.isListening else { return }
                        self.restartRecognitionTask()
                    }
                }
            }
        }
    }
    
    private func restartRecognitionTask() {
        guard isListening else { return }
        startRecognitionTask()
    }
    
    /// Appends incoming audio buffers when wake-word mode is active.
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        detectorQueue.async { [weak self] in
            guard let self = self, self.isListening, let request = self.recognitionRequest else { return }
            var error: NSError?
            HardyFlowTryCatch({
                request.append(buffer)
            }, &error)
            if let error = error {
                print("⚠️ [WakeWordDetector] Buffer append notice: \(error.localizedDescription)")
            }
        }
    }
    
    /// Stops the wake word detector.
    public func stopListening() {
        performOnQueue {
            stopListeningInternal()
        }
    }
    
    private func stopListeningInternal() {
        guard isListening else { return }
        isListening = false
        var error: NSError?
        HardyFlowTryCatch({
            self.recognitionTask?.cancel()
        }, &error)
        recognitionTask = nil
        recognitionRequest = nil
        print("🛑 [WakeWordDetector] Ambient wake word listener stopped.")
    }
    
    /// Robust wake phrase matcher stripping punctuation and checking phrase and proximity.
    public func isWakePhraseDetected(in rawText: String) -> Bool {
        let lower = rawText.lowercased()
        let stripped = lower.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        let tokens = stripped.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }
        
        let cleanedSentence = tokens.joined(separator: " ")
        
        // 1. Direct phrase check in normalized sentence
        for phrase in wakePhrases {
            if cleanedSentence.contains(phrase) {
                return true
            }
        }
        
        // 2. Greeting + Target proximity check (e.g. "hey, hardy" or "hi there hardy")
        for (i, token) in tokens.enumerated() {
            if greetings.contains(token) {
                for offset in 1...2 {
                    if i + offset < tokens.count && wakeTargetWords.contains(tokens[i + offset]) {
                        return true
                    }
                }
            }
        }
        
        // 3. Greeting concatenated without spaces (e.g. "heyhardy", "hihardy")
        for token in tokens {
            if token.hasPrefix("hey") || token.hasPrefix("hi") {
                let suffix = String(token.dropFirst(token.hasPrefix("hey") ? 3 : 2))
                if wakeTargetWords.contains(suffix) {
                    return true
                }
            }
        }
        
        return false
    }
}
