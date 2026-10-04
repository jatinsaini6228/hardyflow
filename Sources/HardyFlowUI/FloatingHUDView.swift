import SwiftUI
import HardyFlowCore

/// Production-grade floating HUD overlay presenting live streaming transcription,
/// interactive audio waveforms, editable text editor, mistake removal alerts, draggable chip,
/// window move drag handle, resizability, and direct paste actions.
public struct FloatingHUDView: View {
    @ObservedObject public var state: AppState = AppState.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 10) {
            // Header: Drag Handle Bar, Status Indicator, Language Quick Switch, and Controls
            HStack(spacing: 8) {
                // Window Move Drag Handle with Grip Icon
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusIndicatorColor.opacity(0.8), radius: 3)
                    
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                
                // Native Window Drag Handle covering the entire middle header bar
                WindowDragHandleView()
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .help("Click and drag anywhere on this header bar to move this card")
                
                // Quick Accent / Locale Switcher
                HStack(spacing: 3) {
                    accentButton(label: "🇮🇳 IN", localeId: "en-IN")
                    accentButton(label: "🇺🇸 US", localeId: "en-US")
                    accentButton(label: "🇮🇳 हिं", localeId: "hi-IN")
                }
                .padding(2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                
                // Cancel / Close Button
                Button(action: {
                    state.cancelRecording()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Cancel dictation without pasting (Esc)")
            }
            .frame(height: 28)
            
            // Granular, Auto-Updating Permission Banner
            if (!state.isMicAuthorized || !state.isSpeechAuthorized || !state.isAccessibilityAuthorized) && !state.isWarningDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor((!state.isMicAuthorized || !state.isSpeechAuthorized) ? .yellow : .orange)
                        .font(.system(size: 13))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(permissionWarningTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(permissionWarningSubtitle)
                            .font(.system(size: 9.5, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Direct Action Button
                    Button(action: {
                        handlePermissionAction()
                    }) {
                        Text(permissionActionTitle)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((!state.isMicAuthorized || !state.isSpeechAuthorized) ? Color.yellow : Color.orange)
                            .foregroundColor(.black)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    // Instant Re-check Button
                    Button(action: {
                        state.refreshPermissions()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(4)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Re-check permissions now")
                    
                    // Dismiss Button
                    Button(action: {
                        withAnimation {
                            state.isWarningDismissed = true
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss warning banner")
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(((!state.isMicAuthorized || !state.isSpeechAuthorized) ? Color.yellow : Color.orange).opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(((!state.isMicAuthorized || !state.isSpeechAuthorized) ? Color.yellow : Color.orange).opacity(0.35), lineWidth: 1)
                        )
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            // Middle 1: Centered Listening Line (Waveform) & Stop Listening Control
            HStack(spacing: 16) {
                Spacer()
                
                // Centered dynamic soundwave
                AudioWaveformView(audioLevel: state.audioLevel, barCount: 15)
                
                // Stop Listening Button (only shown when listening/recording)
                if state.status == .recording || state.status == .listeningWakeWord {
                    Button(action: {
                        state.stopListeningCompletely()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("Stop Listening")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.pink.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.red.opacity(0.35), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Stop listening and turn off microphone immediately")
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
            }
            .padding(.vertical, 6)
            
            // Middle 2: Live Editable Text Box (Down and Full Width)
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    if state.transcribedText.isEmpty {
                        Text("Listening... speak now or type here to edit mistakes manually.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 8)
                            .padding(.leading, 8)
                            .italic()
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $state.transcribedText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.black.opacity(0.28))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 75, maxHeight: .infinity)
                
                // Word Removed Feedback Banner ("No No No")
                if state.didRecentlyRemoveWord {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 11))
                        Text("Mistake removed ('No No No')")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18))
                    .cornerRadius(6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            // Footer: Draggable Text Chip, Action Buttons, and Resize Grabber
            HStack(spacing: 8) {
                if !state.transcribedText.isEmpty {
                    DraggableTextChip(text: state.transcribedText)
                    
                    Button(action: {
                        state.transcribedText = ""
                    }) {
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Clear transcribed text")
                } else {
                    Text("Say 'No No No' to undo last word")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Spacer()
                
                // Copy to Clipboard Button
                Button(action: {
                    copyToClipboard()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(6)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Copy transcribed text to clipboard")
                
                // Direct Paste / Finish Button
                Button(action: {
                    state.stopRecordingAndDeliver()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.doc.on.clipboard")
                            .font(.system(size: 11, weight: .semibold))
                        Text(state.isAutoPasteEnabled ? "Paste (⌥ Space)" : "Finish")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.5, blue: 1.0),
                                Color(red: 0.6, green: 0.3, blue: 0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.blue.opacity(0.4), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help("Finish recording and paste text directly into active application")
                
                // Native Window Resize Handle (smooth AppKit corner dragging)
                WindowResizeHandleView()
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.45))
                            .allowsHitTesting(false)
                    )
                    .help("Drag this corner to smoothly resize the popup card")
            }
        }
        .padding(14)
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
        .onAppear {
            state.refreshPermissions()
        }
    }
    
    private func accentButton(label: String, localeId: String) -> some View {
        let isSelected = state.selectedLocale.identifier == localeId
        return Button(action: {
            state.setLocale(Locale(identifier: localeId))
        }) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? Color.blue.opacity(0.7) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private var statusIndicatorColor: Color {
        switch state.status {
        case .recording:
            return Color.red
        case .listeningWakeWord:
            return Color.cyan
        case .finishing:
            return Color.green
        case .idle:
            return Color.gray
        }
    }
    
    private var statusTitle: String {
        switch state.status {
        case .recording:
            return "Listening..."
        case .listeningWakeWord:
            return "Hey Hardy active"
        case .finishing:
            return "Pasting to App..."
        case .idle:
            return "Ready"
        }
    }
    
    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(state.transcribedText, forType: .string)
    }
    
    // MARK: - Permission Warning Helpers
    private var permissionWarningTitle: String {
        if !state.isMicAuthorized && !state.isSpeechAuthorized {
            return "Microphone & Speech access required"
        } else if !state.isMicAuthorized {
            return "Microphone access required"
        } else if !state.isSpeechAuthorized {
            return "Speech Recognition access required"
        } else {
            return "Accessibility required for auto-paste"
        }
    }
    
    private var permissionWarningSubtitle: String {
        if !state.isMicAuthorized {
            return "Enable Microphone in System Settings to dictate"
        } else if !state.isSpeechAuthorized {
            return "Enable Speech Recognition for offline models"
        } else {
            return "Enable HardyFlow under Accessibility to type text"
        }
    }
    
    private var permissionActionTitle: String {
        if !state.isMicAuthorized {
            return "Grant Mic"
        } else if !state.isSpeechAuthorized {
            return "Grant Speech"
        } else {
            return "Open Settings"
        }
    }
    
    private func handlePermissionAction() {
        if !state.isMicAuthorized {
            state.requestMicrophoneAccess()
        } else if !state.isSpeechAuthorized {
            state.requestSpeechAccess()
        } else {
            state.requestAccessibilityAccess()
        }
    }
}
