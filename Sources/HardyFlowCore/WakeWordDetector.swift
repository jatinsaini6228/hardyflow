import Foundation
import Speech
import AVFoundation

/// Monitors continuous ambient background audio buffers specifically listening for the "Hey Hardy" wake phrase.
/// Transitions the app into full dictation mode upon detection.
public final class WakeWordDetector: @unchecked Sendable {
    public static let shared = WakeWordDetector()
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let detectorQueue = DispatchQueue(label: "com.hardyflow.wakeword", qos: .userInitiated)
    private static let queueKey = DispatchSpecificKey<Void>()
    
    public private(set) var isListening: Bool = false
    
    /// Callback triggered when the wake word is verified in the ambient audio stream.
    public var onWakeWordDetected: (() -> Void)?
    
    /// Supported wake phrases for hands-free activation.
    public let wakePhrases: [String] = [
        "hey hardy",
        "hey hardi",
        "hi hardy",
        "hi hardi",
        "ok hardy",
        "ok hardi",
        "hardy flow",
        "hardyflow",
        "hey wisper",
        "hey whisper",
        "hi wisper"
    ]
    
    private init() {
        detectorQueue.setSpecific(key: Self.queueKey, value: ())
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    private func performOnQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return try block()
        } else {
            return try detectorQueue.sync(execute: block)
        }
    }
    
    /// Starts background ambient listening for the wake word.
    public func startListening() {
        performOnQueue {
            guard !isListening else { return }
            
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                print("⚠️ [WakeWordDetector] Speech recognizer unavailable for wake word.")
                return
            }
            
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            
            self.recognitionRequest = request
            
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] (result, error) in
                guard let self = self else { return }
                
                if let result = result {
                    let transcribed = result.bestTranscription.formattedString.lowercased()
                    
                    if self.containsWakePhrase(in: transcribed) {
                        print("✨ [WakeWordDetector] Wake word detected: '\(transcribed)'")
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
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 203) {
                        return
                    }
                    print("⚠️ [WakeWordDetector] Error: \(error.localizedDescription)")
                }
            }
            
            isListening = true
            print("👂 [WakeWordDetector] Ambient wake word listener active ('Hey Hardy').")
        }
    }
    
    /// Appends incoming audio buffers when wake-word mode is active.
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        detectorQueue.async { [weak self] in
            guard let self = self, self.isListening else { return }
            self.recognitionRequest?.append(buffer)
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
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        print("🛑 [WakeWordDetector] Ambient wake word listener stopped.")
    }
    
    private func containsWakePhrase(in text: String) -> Bool {
        for phrase in wakePhrases {
            if text.contains(phrase) {
                return true
            }
        }
        return false
    }
}
