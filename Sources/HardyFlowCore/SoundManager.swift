import Foundation
import AppKit

/// Provides clean, non-intrusive auditory cues for recording state changes, wake-word detection, and voice corrections.
public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()
    
    public var isSoundEnabled: Bool = true
    
    private init() {}
    
    /// Plays an auditory cue indicating dictation has started.
    public func playStartCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Tink")
    }
    
    /// Plays an auditory cue indicating dictation has completed.
    public func playStopCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Pop")
    }
    
    /// Plays a distinct cue when the 'Hey Hardy' wake-word is detected.
    public func playWakeWordCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Glass")
    }
    
    /// Plays a subtle click/pop cue when 'No No No' successfully deletes a word.
    public func playWordRemovedCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Bottle")
    }
    
    /// Plays an alert sound when permissions are missing or an error occurs.
    public func playErrorCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Basso")
    }
    
    /// Plays an auditory cue indicating a paste operation has completed.
    public func playPasteCue() {
        guard isSoundEnabled else { return }
        playSystemSound(named: "Blow")
    }
    
    private func playSystemSound(named name: String) {
        DispatchQueue.main.async {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.play()
            }
        }
    }
}
