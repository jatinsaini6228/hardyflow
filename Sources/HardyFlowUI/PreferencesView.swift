import SwiftUI
import Speech
import HardyFlowCore

/// Comprehensive Preferences panel for HardyFlow configuration:
/// language accents, hotkeys, "Hey Hardy" wake word, silence timeout, output modes, and permissions.
public struct PreferencesView: View {
    @ObservedObject public var state: AppState = AppState.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("HardyFlow")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Universal Speech-to-Text & Voice Dictation")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("v1.0.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding()
            
            Divider()
            
            // Tab Selector
            Picker("", selection: $state.selectedPreferencesTab) {
                Text("General").tag(0)
                Text("Voice & Wake").tag(1)
                Text("Output").tag(2)
                Text("Permissions").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch state.selectedPreferencesTab {
                    case 0:
                        generalSettingsTab
                    case 1:
                        voiceSettingsTab
                    case 2:
                        outputSettingsTab
                    case 3:
                        permissionsTab
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
            .frame(height: 320)
            
            Divider()
            
            // Footer
            HStack {
                Text("100% Free & On-Device Speech Recognition")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 500, height: 440)
        .onAppear {
            state.refreshPermissions()
        }
    }
    
    // MARK: - General Tab
    private var generalSettingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("Speech Language & Accent", systemImage: "globe")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select your primary spoken language or regional accent:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Picker("Active Locale:", selection: Binding(
                        get: { state.selectedLocale.identifier },
                        set: { newId in
                            state.setLocale(Locale(identifier: newId))
                        }
                    )) {
                        Section(header: Text("Recommended Accents")) {
                            Text("🇮🇳 English (India) [en-IN]").tag("en-IN")
                            Text("🇮🇳 Hindi (India) [hi-IN]").tag("hi-IN")
                            Text("🇺🇸 English (United States) [en-US]").tag("en-US")
                            Text("🇬🇧 English (United Kingdom) [en-GB]").tag("en-GB")
                            Text("🇨🇦 English (Canada) [en-CA]").tag("en-CA")
                            Text("🇦🇺 English (Australia) [en-AU]").tag("en-AU")
                        }
                        
                        Section(header: Text("All Supported Locales (\(SpeechRecognitionService.availableLocales.count))")) {
                            ForEach(SpeechRecognitionService.availableLocales, id: \.identifier) { loc in
                                Text("\(loc.localizedString(forIdentifier: loc.identifier) ?? loc.identifier) [\(loc.identifier)]")
                                    .tag(loc.identifier)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(8)
            }
            
            GroupBox(label: Label("Global Activation Shortcut", systemImage: "keyboard")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Dictation Hotkey:")
                            .font(.system(size: 12, weight: .medium))
                        Text("Press to toggle speech-to-text from inside any background app.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("⌥ Space")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Voice & Wake Tab
    private var voiceSettingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("Microphone Input Device", systemImage: "mic.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active microphone for high-fidelity dictation:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(.blue)
                        Text(AudioEngineManager.shared.getAvailableInputDevices().first(where: { $0.isBuiltIn })?.name ?? "Studio Microphone")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("High Fidelity (48kHz)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    
                    Text("💡 HardyFlow automatically routes input to the MacBook built-in studio microphone to avoid low-bitrate Bluetooth telephony (SCO) compression when AirPods are connected.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            
            GroupBox(label: Label("Wake-Word Listening ('Hey Hardy')", systemImage: "ear")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Always listen for 'Hey Hardy' activation phrase", isOn: $state.isWakeWordEnabled)
                        .font(.system(size: 13, weight: .medium))
                    
                    Text("When active, HardyFlow continuously listens in the background. Saying 'Hey Hardy' immediately triggers dictation without pressing any keys.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            
            GroupBox(label: Label("Automatic Silence Timeout", systemImage: "timer")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Silence duration before auto-pasting:")
                            .font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.1f seconds", state.silenceTimeout))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    
                    Slider(value: $state.silenceTimeout, in: 1.0...4.0, step: 0.2)
                }
                .padding(8)
            }
            
            GroupBox(label: Label("Voice Mistake Removal Command", systemImage: "arrow.uturn.backward")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keyword: \"No No No\"")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    
                    Text("Saying 'No No No' (or 'No No No Remove') while speaking will instantly excise the command and erase the preceding word from your dictation buffer. Saying it multiple times removes multiple words.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Output Tab
    private var outputSettingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("Delivery Mode", systemImage: "arrow.right.doc.on.clipboard")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Direct Auto-Paste into background application", isOn: $state.isAutoPasteEnabled)
                        .font(.system(size: 13, weight: .medium))
                    
                    Text("When enabled, HardyFlow restores focus to the app you were typing in (Slack, Chrome, Notion, etc.) and automatically types Command+V. You can also drag the text chip from the HUD at any time.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Toggle("Play audio feedback cues", isOn: $state.isSoundEffectsEnabled)
                        .font(.system(size: 12))
                }
                .padding(8)
            }
            
            if !state.recentTranscriptions.isEmpty {
                GroupBox(label: Label("Recent Transcriptions", systemImage: "clock")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(state.recentTranscriptions.prefix(3), id: \.self) { item in
                            HStack {
                                Text(item)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item, forType: .string)
                                }
                                .font(.system(size: 10))
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
    
    // MARK: - Permissions Tab
    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("System Privacy Permissions", systemImage: "lock.shield")) {
                VStack(spacing: 12) {
                    permissionRow(
                        title: "Microphone Access",
                        subtitle: "Required to record your speech for dictation.",
                        isGranted: state.isMicAuthorized,
                        actionTitle: "Grant Access",
                        action: {
                            state.requestMicrophoneAccess()
                        }
                    )
                    
                    Divider()
                    
                    permissionRow(
                        title: "Speech Recognition",
                        subtitle: "Required for offline, on-device audio transcription.",
                        isGranted: state.isSpeechAuthorized,
                        actionTitle: SFSpeechRecognizer.authorizationStatus() == .denied ? "Open Settings" : "Grant Access",
                        action: {
                            if SFSpeechRecognizer.authorizationStatus() == .denied {
                                AppState.openSpeechSettings()
                            } else {
                                SpeechRecognitionService.requestAuthorization { granted in
                                    state.isSpeechAuthorized = granted
                                }
                            }
                        }
                    )
                    
                    Divider()
                    
                    permissionRow(
                        title: "Accessibility",
                        subtitle: "Required to synthesize Command+V paste into background apps.",
                        isGranted: state.isAccessibilityAuthorized,
                        actionTitle: "Open Settings",
                        action: {
                            PasteService.openAccessibilitySettings()
                        }
                    )
                }
                .padding(8)
            }
        }
    }
    
    private func permissionRow(title: String, subtitle: String, isGranted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isGranted ? .green : .orange)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button(actionTitle) {
                    action()
                }
                .font(.system(size: 11))
            }
        }
    }
}

/// Window controller managing the Preferences window instance.
public final class PreferencesWindowController: NSObject, @unchecked Sendable {
    public static let shared = PreferencesWindowController()
    private var window: NSWindow?
    
    public func showWindow() {
        DispatchQueue.main.async {
            if self.window == nil {
                let hosting = NSHostingController(rootView: PreferencesView())
                let win = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                win.title = "HardyFlow Preferences & Permissions"
                win.contentViewController = hosting
                win.center()
                win.isReleasedWhenClosed = false
                win.level = .floating
                self.window = win
            }
            self.window?.center()
            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
