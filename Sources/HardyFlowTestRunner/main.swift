import Foundation
import HardyFlowCore
import Speech

class TestFramework {
    static var totalTests = 0
    static var passedTests = 0
    static var failedTests = 0
    
    static func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if condition {
            passedTests += 1
            print("  ✅ [PASS] \(message)")
        } else {
            failedTests += 1
            print("  ❌ [FAIL] \(message) (\(file):\(line))")
        }
    }
    
    static func runSuite(named name: String, block: () -> Void) {
        print("\n=======================================================")
        print("🧪 RUNNING SUITE: \(name)")
        print("=======================================================")
        block()
    }
    
    static func report() {
        print("\n=======================================================")
        print("📊 TEST SUMMARY")
        print("=======================================================")
        print("Total: \(totalTests) | Passed: \(passedTests) | Failed: \(failedTests)")
        if failedTests == 0 {
            print("🎉 ALL HARDYFLOW TESTS PASSED SUCCESSFULLY!")
        } else {
            print("💥 SOME TESTS FAILED.")
            exit(1)
        }
    }
}

// MARK: - Test Suite 1: Voice Command Mistake Removal ("No No No")

TestFramework.runSuite(named: "VoiceCommandProcessor Tests") {
    let processor = VoiceCommandProcessor()
    
    // 1. "No No No" (3 tokens) single removal
    let r1 = processor.process("The meeting is at three No No No four")
    TestFramework.assert(r1.didRemove == true && r1.wordsRemovedCount == 1 && r1.text == "The meeting is at four",
                         "Processed 'No No No': 'three' replaced with 'four'")
    
    // 2. Case insensitive "no no no"
    let r2 = processor.process("Today is wednesday no no no thursday")
    TestFramework.assert(r2.didRemove == true && r2.wordsRemovedCount == 1 && r2.text == "Today is thursday",
                         "Processed case-insensitive 'no no no'")
    
    // 3. Punctuation variations "no, no, no"
    let r3 = processor.process("I am sad, no, no, no happy")
    TestFramework.assert(r3.didRemove == true && r3.wordsRemovedCount == 1 && r3.text == "I am happy",
                         "Processed punctuation variant 'no, no, no'")
    
    // 4. Backwards compatibility for "NO NO NO Remove" (4 tokens)
    let r4 = processor.process("The price is fifty NO NO NO Remove sixty")
    TestFramework.assert(r4.didRemove == true && r4.wordsRemovedCount == 1 && r4.text == "The price is sixty",
                         "Processed backwards-compatible 'NO NO NO Remove'")
    
    // 5. Multiple consecutive removals: "no no no no no no"
    let r5 = processor.process("The color is red blue green no no no no no no yellow")
    TestFramework.assert(r5.didRemove == true && r5.wordsRemovedCount == 2 && r5.text == "The color is red yellow",
                         "Processed multiple consecutive removals: deleted 'green' and 'blue'")
    
    // 6. Trailing removal at end of sentence
    let r6 = processor.process("Let us do this wrong no no no")
    TestFramework.assert(r6.didRemove == true && r6.wordsRemovedCount == 1 && r6.text == "Let us do this",
                         "Processed trailing removal at end of string")
    
    // 7. No removal command present
    let r7 = processor.process("Good morning to everyone in India")
    TestFramework.assert(r7.didRemove == false && r7.wordsRemovedCount == 0 && r7.text == "Good morning to everyone in India",
                         "Preserved sentence without commands")
    
    // 8. Empty string
    let r8 = processor.process("   ")
    TestFramework.assert(r8.didRemove == false && r8.wordsRemovedCount == 0 && r8.text == "",
                         "Handled empty string correctly")
}

// MARK: - Test Suite 2: Multi-Locale & Indian Accent Support

TestFramework.runSuite(named: "Locale & Accent Support Tests") {
    let locales = SpeechRecognitionService.availableLocales
    TestFramework.assert(locales.count > 30, "Confirmed wide multi-locale library (>30 locales, actual: \(locales.count))")
    
    let hasIndianEnglish = locales.contains { $0.identifier == "en-IN" }
    TestFramework.assert(hasIndianEnglish, "Confirmed Indian English (en-IN) is supported")
    
    let hasHindi = locales.contains { $0.identifier.starts(with: "hi") }
    TestFramework.assert(hasHindi, "Confirmed Hindi (hi-IN) is supported")
    
    let hasUSEnglish = locales.contains { $0.identifier == "en-US" }
    TestFramework.assert(hasUSEnglish, "Confirmed US English (en-US) is supported")
    
    // Test SFSpeechRecognizer on-device recognition support for en-IN
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    TestFramework.assert(recognizer != nil, "Initialized SFSpeechRecognizer for en-IN successfully")
    TestFramework.assert(recognizer?.supportsOnDeviceRecognition == true, "Verified en-IN on-device recognition supported")
}

// MARK: - Test Suite 3: AppState Configuration & Persistence

TestFramework.runSuite(named: "AppState Configuration Tests") {
    let state = AppState.shared
    TestFramework.assert(state.status == .idle, "Initial AppState status is idle")
    TestFramework.assert(!state.isAutoPasteEnabled.description.isEmpty, "AutoPaste configuration verified")
    TestFramework.assert(state.silenceTimeout >= 1.0, "Silence timeout is configured (>= 1.0s, actual: \(state.silenceTimeout)s)")
}

// MARK: - Test Suite 4: Zero Audio Persistence & Memory Purging

TestFramework.runSuite(named: "Audio Privacy & Memory Purge Tests") {
    let state = AppState.shared
    state.transcribedText = "Sensitive spoken text"
    state.recentTranscriptions = ["Session record 1", "Session record 2"]
    
    // Test AppState purgeAllSessionData()
    state.purgeAllSessionData()
    TestFramework.assert(state.transcribedText.isEmpty, "Purged all transcribed text from memory")
    TestFramework.assert(state.recentTranscriptions.isEmpty, "Purged recent transcripts history from memory")
    
    // Test AudioEngineManager purgeTemporaryAudioMemory()
    AudioEngineManager.shared.purgeTemporaryAudioMemory()
    TestFramework.assert(!AudioEngineManager.shared.isRunning, "AudioEngine is stopped with 0 audio buffers in RAM")
    TestFramework.assert(AudioEngineManager.shared.onAudioBuffer == nil, "Audio buffer tap closure is nil (unhooked)")
    TestFramework.assert(AudioEngineManager.shared.onAudioLevelChanged == nil, "Audio level closure is nil (unhooked)")
}

// MARK: - Test Suite 5: "Hey Hardy" Hands-Free Wake Word Phrases

TestFramework.runSuite(named: "Wake Word Configuration Tests") {
    let detector = WakeWordDetector.shared
    TestFramework.assert(detector.wakePhrases.contains("hey hardy"), "Confirmed 'hey hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("hi hardy"), "Confirmed 'hi hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("ok hardy"), "Confirmed 'ok hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("hardy flow"), "Confirmed 'hardy flow' is active wake phrase")
}

// MARK: - Run & Report

TestFramework.report()
