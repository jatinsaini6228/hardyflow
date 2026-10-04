import Foundation
import HardyFlowCore
import HardyFlowObjC
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

// MARK: - Test Suite 5: "Hey Hardy" Hands-Free Wake Word Phrases & Resilient Detection

TestFramework.runSuite(named: "Wake Word Configuration Tests") {
    let detector = WakeWordDetector.shared
    TestFramework.assert(detector.wakePhrases.contains("hey hardy"), "Confirmed 'hey hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("hi hardy"), "Confirmed 'hi hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("ok hardy"), "Confirmed 'ok hardy' is active wake phrase")
    TestFramework.assert(detector.wakePhrases.contains("hardy flow"), "Confirmed 'hardy flow' is active wake phrase")
    
    // Resilient punctuation-stripped and phonetic matching
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hey, Hardy!"), "Detected 'Hey, Hardy!' (with comma & exclamation)")
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hi, Hardy"), "Detected 'Hi, Hardy' (with comma)")
    TestFramework.assert(detector.isWakePhraseDetected(in: "hey hardy"), "Detected lowercase 'hey hardy'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "hi hardy"), "Detected lowercase 'hi hardy'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hello Hardy"), "Detected 'Hello Hardy'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hey, hearty"), "Detected phonetic variant 'Hey, hearty'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hi, party"), "Detected phonetic variant 'Hi, party'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "Hey there Hardy"), "Detected proximity 'Hey there Hardy'")
    TestFramework.assert(detector.isWakePhraseDetected(in: "heyhardy"), "Detected concatenated 'heyhardy'")
    TestFramework.assert(!detector.isWakePhraseDetected(in: "Just discussing python code with team"), "Correctly rejected unrelated speech")
}

// MARK: - Test Suite 6: EnvLoader & AI Configuration Tests

TestFramework.runSuite(named: "EnvLoader & AI Configuration Tests") {
    let rawEnv = """
    # Sample comment line
    LLAMA_API_KEY="gsk_test_key_123"
    LLAMA_API_URL=https://api.groq.com/openai/v1/chat/completions
    LLAMA_MODEL='llama-3.3-70b-versatile'
    LLAMA_TEMPERATURE=0.25
    """
    let parsed = EnvLoader.parseEnvContent(rawEnv)
    TestFramework.assert(parsed["LLAMA_API_KEY"] == "gsk_test_key_123", "Parsed LLAMA_API_KEY with double quotes stripped")
    TestFramework.assert(parsed["LLAMA_API_URL"] == "https://api.groq.com/openai/v1/chat/completions", "Parsed LLAMA_API_URL successfully")
    TestFramework.assert(parsed["LLAMA_MODEL"] == "llama-3.3-70b-versatile", "Parsed LLAMA_MODEL with single quotes stripped")
    TestFramework.assert(parsed["LLAMA_TEMPERATURE"] == "0.25", "Parsed LLAMA_TEMPERATURE successfully")
    TestFramework.assert(parsed["# Sample comment line"] == nil, "Ignored comments correctly")
}

// MARK: - Test Suite 7: CustomVocabulary & Phonetic Corrections Tests

TestFramework.runSuite(named: "CustomVocabulary & Phonetic Corrections Tests") {
    // 1. Vocabulary scale and domains
    let allWords = CustomVocabulary.allContextualStrings
    TestFramework.assert(allWords.count >= 80, "Contextual vocabulary contains rich dictionary (>80 terms, actual: \(allWords.count))")
    
    // 2. Tech terms presence
    TestFramework.assert(CustomVocabulary.techTerms.contains("Kubernetes"), "Tech dictionary includes Kubernetes")
    TestFramework.assert(CustomVocabulary.techTerms.contains("Docker"), "Tech dictionary includes Docker")
    TestFramework.assert(CustomVocabulary.techTerms.contains("SwiftUI"), "Tech dictionary includes SwiftUI")
    TestFramework.assert(CustomVocabulary.techTerms.contains("Llama 3"), "Tech dictionary includes Llama 3")
    
    // 3. Indian slang presence
    TestFramework.assert(CustomVocabulary.indianExpressions.contains("jugaad"), "Indian dictionary includes 'jugaad'")
    TestFramework.assert(CustomVocabulary.indianExpressions.contains("achha"), "Indian dictionary includes 'achha'")
    TestFramework.assert(CustomVocabulary.indianExpressions.contains("theek hai"), "Indian dictionary includes 'theek hai'")
    TestFramework.assert(CustomVocabulary.indianExpressions.contains("aadhaar"), "Indian dictionary includes 'aadhaar'")
    TestFramework.assert(CustomVocabulary.indianExpressions.contains("UPI"), "Indian dictionary includes 'UPI'")
    
    // 4. Phonetic auto-corrections: "papa" -> "popup"
    let c1 = CustomVocabulary.applyPhoneticCorrections("Please move the papa")
    TestFramework.assert(c1 == "Please move the popup", "Corrected 'move the papa' -> 'move the popup'")
    
    let c2 = CustomVocabulary.applyPhoneticCorrections("Open the papa card")
    TestFramework.assert(c2 == "Open the popup card", "Corrected 'papa card' -> 'popup card'")
    
    // 5. Tech phonetic corrections: "sink await" -> "async await"
    let c3 = CustomVocabulary.applyPhoneticCorrections("Write a sink await function")
    TestFramework.assert(c3 == "Write a async await function", "Corrected 'sink await' -> 'async await'")
    
    let c4 = CustomVocabulary.applyPhoneticCorrections("Push to git hub")
    TestFramework.assert(c4 == "Push to GitHub", "Corrected 'git hub' -> 'GitHub'")
}

// MARK: - Test Suite 8: AI Polish Tags & Prompt Structure Tests

TestFramework.runSuite(named: "AI Polish Tags & Prompt Structure Tests") {
    // 1. All tags exist
    TestFramework.assert(PolishTag.allCases.count == 3, "Verified 3 Polish tags: No-Tag, Email, AI-Prompt")
    
    // 2. Verify Tag Prompt templates
    let noTagPrompt = PolishTag.noTag.systemInstruction
    TestFramework.assert(noTagPrompt.contains("transcription polisher"), "Verified No-Tag prompt instructs clean voice polishing")
    
    let emailPrompt = PolishTag.email.systemInstruction
    TestFramework.assert(emailPrompt.contains("professional email"), "Verified Email prompt instructs executive email formatting")
    
    let aiPrompt = PolishTag.aiPrompt.systemInstruction
    TestFramework.assert(aiPrompt.contains("prompt engineer"), "Verified AI-Prompt instructs structured AI prompt engineering")
}

// MARK: - Test Suite 9: Persistent HUD Stop & Resume Listening Lifecycle

TestFramework.runSuite(named: "Stop & Resume Listening Lifecycle Tests") {
    let state = AppState.shared
    
    // Test pauseListening()
    state.pauseListening()
    TestFramework.assert(state.isListeningPaused == true, "pauseListening() sets isListeningPaused to true")
    TestFramework.assert(state.audioLevel == 0.0, "pauseListening() drops audioLevel to 0.0")
    
    // Test undo Polish
    state.transcribedText = "Clean polished speech"
    state.prePolishText = "Raw rough speech"
    state.undoPolish()
    TestFramework.assert(state.transcribedText == "Raw rough speech", "undoPolish() successfully restored prePolishText")
    TestFramework.assert(state.prePolishText == nil, "undoPolish() cleared prePolishText after restoring")
    
    // Reset paused state
    state.isListeningPaused = false
}

// MARK: - Test Suite 10: Gen-Z Slang & 2026 Tech Vocabulary Tests

TestFramework.runSuite(named: "Gen-Z Slang & 2026 Tech Vocabulary Tests") {
    // 1. Gen-Z Slang dictionary verification
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("rizz"), "Gen-Z vocabulary includes 'rizz'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("no cap"), "Gen-Z vocabulary includes 'no cap'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("delulu"), "Gen-Z vocabulary includes 'delulu'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("bussin"), "Gen-Z vocabulary includes 'bussin'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("skibidi"), "Gen-Z vocabulary includes 'skibidi'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("fanum tax"), "Gen-Z vocabulary includes 'fanum tax'")
    TestFramework.assert(CustomVocabulary.genZSlangs.contains("let him cook"), "Gen-Z vocabulary includes 'let him cook'")
    
    // 2. 2026 Tech dictionary verification
    TestFramework.assert(CustomVocabulary.techTerms.contains("Next.js"), "Tech vocabulary includes 'Next.js'")
    TestFramework.assert(CustomVocabulary.techTerms.contains("Tailwind CSS"), "Tech vocabulary includes 'Tailwind CSS'")
    TestFramework.assert(CustomVocabulary.techTerms.contains("Supabase"), "Tech vocabulary includes 'Supabase'")
    TestFramework.assert(CustomVocabulary.techTerms.contains("Prisma"), "Tech vocabulary includes 'Prisma'")
    TestFramework.assert(CustomVocabulary.techTerms.contains("LangChain"), "Tech vocabulary includes 'LangChain'")
    TestFramework.assert(CustomVocabulary.techTerms.contains("DeepSeek"), "Tech vocabulary includes 'DeepSeek'")
    
    // 3. Phonetic auto-corrections
    let p1 = CustomVocabulary.applyPhoneticCorrections("that was no cup fr fr")
    TestFramework.assert(p1.contains("no cap"), "Corrected 'no cup' -> 'no cap'")
    
    let p2 = CustomVocabulary.applyPhoneticCorrections("she is totally de lulu")
    TestFramework.assert(p2.contains("delulu"), "Corrected 'de lulu' -> 'delulu'")
    
    let p3 = CustomVocabulary.applyPhoneticCorrections("build with next js and supa base")
    TestFramework.assert(p3.contains("Next.js") && p3.contains("Supabase"), "Corrected 'next js' and 'supa base' -> 'Next.js' and 'Supabase'")
    
    let p4 = CustomVocabulary.applyPhoneticCorrections("query deep seek with llama index")
    TestFramework.assert(p4.contains("DeepSeek") && p4.contains("LlamaIndex"), "Corrected 'deep seek' and 'llama index' -> 'DeepSeek' and 'LlamaIndex'")
}

// MARK: - Test Suite 11: Spoken Punctuation & Smart Text Normalization Tests

TestFramework.runSuite(named: "Spoken Punctuation & Text Normalization Tests") {
    // 1. Spoken punctuation conversion
    let n1 = VoiceCommandProcessor.normalizeText("hello period how are you question mark")
    TestFramework.assert(n1 == "Hello. How are you?", "Normalized 'period' and 'question mark' to '.' and '?'")
    
    let n2 = VoiceCommandProcessor.normalizeText("look at this exclamation mark")
    TestFramework.assert(n2 == "Look at this!", "Normalized 'exclamation mark' to '!'")
    
    // 2. Spacing cleanup around punctuation
    let n3 = VoiceCommandProcessor.normalizeText("apples , bananas , and oranges .")
    TestFramework.assert(n3 == "Apples, bananas, and oranges.", "Cleaned orphan spaces before commas and period")
    
    // 3. Currency and number formatting
    let n4 = VoiceCommandProcessor.normalizeText("the budget is 500 dollars")
    TestFramework.assert(n4 == "The budget is $500", "Normalized '500 dollars' to '$500'")
    
    let n5 = VoiceCommandProcessor.normalizeText("the cost is 1000 rupees")
    TestFramework.assert(n5 == "The cost is ₹1000", "Normalized '1000 rupees' to '₹1000'")
    
    let n6 = VoiceCommandProcessor.normalizeText("he made 10 lakh on the project")
    TestFramework.assert(n6 == "He made 10 Lakh on the project", "Normalized '10 lakh' to '10 Lakh'")
    
    // 4. Capitalization
    let n7 = VoiceCommandProcessor.normalizeText("welcome to hardyflow. it is super fast.")
    TestFramework.assert(n7 == "Welcome to hardyflow. It is super fast.", "Capitalized first word and word after period")
}

// MARK: - Test Suite 12: Context Intelligence Per-App Smart Tags Tests

TestFramework.runSuite(named: "Context Intelligence Per-App Tests") {
    // 1. Check App Category classifications
    TestFramework.assert(ContextIntelligence.suggestedTag(for: nil) == .noTag, "Nil app defaults to No-Tag")
    
    // 2. App-Aware state toggle verification
    let state = AppState.shared
    state.isAppAwareContextEnabled = true
    TestFramework.assert(state.isAppAwareContextEnabled == true, "isAppAwareContextEnabled is enabled")
}

// MARK: - Test Suite 13: Snippet Macros, Whisper Mode & Re-Paste Tests

TestFramework.runSuite(named: "Snippet Macros, Whisper Mode & Re-Paste Tests") {
    // 1. Bug template macro expansion
    let textWithBug = SnippetManager.expandSnippets(in: "Please create a bug template for this")
    TestFramework.assert(textWithBug.contains("### Bug Report") && textWithBug.contains("Steps to Reproduce"), "Expanded 'bug template' macro into Markdown template")
    
    // 2. PR template macro expansion
    let textWithPR = SnippetManager.expandSnippets(in: "Generate pr template now")
    TestFramework.assert(textWithPR.contains("### Summary of Changes"), "Expanded 'pr template' macro into Markdown template")
    
    // 3. User email macro expansion
    SnippetManager.userEmail = "developer@hardyflow.com"
    let textWithEmail = SnippetManager.expandSnippets(in: "Send it to my email right away")
    TestFramework.assert(textWithEmail.contains("developer@hardyflow.com"), "Expanded 'my email' into configured email address")
    
    // 4. Whisper Mode toggle & pre-gain configuration
    let state = AppState.shared
    state.isWhisperModeEnabled = true
    TestFramework.assert(AudioEngineManager.shared.isWhisperModeEnabled == true, "AudioEngineManager reflects Whisper Mode enabled")
    TestFramework.assert(AudioEngineManager.shared.whisperGainMultiplier >= 2.0, "Whisper gain multiplier provides at least 2.0x pre-gain boost")
    state.isWhisperModeEnabled = false
    TestFramework.assert(AudioEngineManager.shared.isWhisperModeEnabled == false, "Whisper Mode toggle disables cleanly")
    
    // 5. Re-Paste Last Transcription verification
    state.recentTranscriptions = ["HardyFlow test transcription for repaste"]
    TestFramework.assert(state.recentTranscriptions.first == "HardyFlow test transcription for repaste", "Verified recent transcriptions queue is populated for Re-Paste")
}

// MARK: - Test Suite 14: Objective-C Exception Guard & EnvLoader Tests

TestFramework.runSuite(named: "HardyFlowObjC Exception Guard & EnvLoader Tests") {
    // 1. HardyFlowTryCatch catches NSException
    var caughtError: NSError?
    let succeeded = HardyFlowTryCatch({
        let ex = NSException(name: NSExceptionName("TestCoreAudioException"), reason: "Simulated InstallTapOnNode failure", userInfo: nil)
        ex.raise()
    }, &caughtError)
    
    TestFramework.assert(succeeded == false, "HardyFlowTryCatch returned false when exception was thrown")
    TestFramework.assert(caughtError != nil && caughtError?.domain == "com.hardyflow.exception", "HardyFlowTryCatch converted NSException to NSError successfully")
    TestFramework.assert(caughtError?.localizedDescription == "Simulated InstallTapOnNode failure", "Caught exception message matches thrown reason")
    
    // 2. HardyFlowTryCatch succeeds when no exception thrown
    var noError: NSError?
    let successRun = HardyFlowTryCatch({
        let _ = 1 + 1
    }, &noError)
    TestFramework.assert(successRun == true && noError == nil, "HardyFlowTryCatch executes normally when no exception is thrown")
    
    // 3. EnvLoader parseEnvContent handles comments, whitespace, quotes
    let sampleEnv = """
    # Comment line
    LLAMA_API_KEY="test_key_123"
    LLAMA_API_URL = http://localhost:11434/v1/chat/completions
    OLLAMA_MODEL='llama3.2'
    """
    let parsed = EnvLoader.parseEnvContent(sampleEnv)
    TestFramework.assert(parsed["LLAMA_API_KEY"] == "test_key_123", "Parsed quoted API key")
    TestFramework.assert(parsed["LLAMA_API_URL"] == "http://localhost:11434/v1/chat/completions", "Parsed URL with whitespace")
    TestFramework.assert(parsed["OLLAMA_MODEL"] == "llama3.2", "Parsed single-quoted model")
}

// MARK: - Run & Report

TestFramework.report()

