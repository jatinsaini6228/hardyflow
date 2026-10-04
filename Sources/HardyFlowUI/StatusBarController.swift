import Foundation
import AppKit
import Combine
import HardyFlowCore

/// Manages the macOS menu bar status item, dynamic microphone icon states,
/// quick language switching, wake-word toggle, and preferences.
public final class StatusBarController: NSObject, @unchecked Sendable {
    public static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        super.init()
        setupStatusItem()
        observeAppState()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "HardyFlow") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🎙️"
            }
            button.imagePosition = .imageLeft
        }
        
        buildMenu()
    }
    
    private func observeAppState() {
        AppState.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateStatusIcon(for: status)
                self?.buildMenu()
            }
            .store(in: &cancellables)
        
        AppState.shared.$selectedLocale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusIcon(for status: AppState.RecordingStatus) {
        guard let button = statusItem?.button else { return }
        
        switch status {
        case .recording:
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = image?.withSymbolConfiguration(config) ?? image
            button.title = " Rec"
        case .listeningWakeWord:
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Listening for Hey Hardy")
            image?.isTemplate = true
            button.image = image
            button.title = " 👂"
        case .finishing:
            let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Pasting")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            button.image = image?.withSymbolConfiguration(config) ?? image
            button.title = ""
        case .idle:
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "HardyFlow Ready")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        }
    }
    
    public func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Header
        let titleItem = NSMenuItem(title: "HardyFlow Speech-to-Text", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let boldFont = NSFont.boldSystemFont(ofSize: 12) as NSFont? {
            titleItem.attributedTitle = NSAttributedString(
                string: "HardyFlow Speech-to-Text",
                attributes: [.font: boldFont]
            )
        }
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Dictation Action
        let isRecording = AppState.shared.status == .recording
        let dictationTitle = isRecording ? "Stop Dictation & Paste" : "Start Dictation (⌥ Space)"
        let dictationItem = NSMenuItem(title: dictationTitle, action: #selector(toggleDictation), keyEquivalent: " ")
        dictationItem.keyEquivalentModifierMask = .option
        dictationItem.target = self
        menu.addItem(dictationItem)
        
        // Wake Word Toggle
        let wakeTitle = "Listen for 'Hey Hardy'"
        let wakeItem = NSMenuItem(title: wakeTitle, action: #selector(toggleWakeWord), keyEquivalent: "")
        wakeItem.state = AppState.shared.isWakeWordEnabled ? .on : .off
        wakeItem.target = self
        menu.addItem(wakeItem)
        
        // Auto-Paste Toggle
        let pasteItem = NSMenuItem(title: "Direct Auto-Paste", action: #selector(toggleAutoPaste), keyEquivalent: "")
        pasteItem.state = AppState.shared.isAutoPasteEnabled ? .on : .off
        pasteItem.target = self
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Language Submenu
        let langMenu = NSMenu(title: "Language & Accent")
        let currentLocaleId = AppState.shared.selectedLocale.identifier
        
        let popularLocales = [
            ("🇮🇳 English (India)", "en-IN"),
            ("🇮🇳 Hindi (India)", "hi-IN"),
            ("🇺🇸 English (United States)", "en-US"),
            ("🇬🇧 English (United Kingdom)", "en-GB"),
            ("🇨🇦 English (Canada)", "en-CA"),
            ("🇦🇺 English (Australia)", "en-AU"),
            ("🇪🇸 Spanish", "es-ES"),
            ("🇫🇷 French", "fr-FR"),
            ("🇩🇪 German", "de-DE"),
            ("🇯🇵 Japanese", "ja-JP")
        ]
        
        for (name, id) in popularLocales {
            let item = NSMenuItem(title: name, action: #selector(selectLocale(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            if id == currentLocaleId {
                item.state = .on
            }
            langMenu.addItem(item)
        }
        
        let langSubmenuItem = NSMenuItem(title: "Language & Accent", action: nil, keyEquivalent: "")
        langSubmenuItem.submenu = langMenu
        menu.addItem(langSubmenuItem)
        
        // Recent Transcriptions Submenu
        if !AppState.shared.recentTranscriptions.isEmpty {
            let recentMenu = NSMenu(title: "Recent Transcriptions")
            for text in AppState.shared.recentTranscriptions {
                let item = NSMenuItem(title: text, action: #selector(copyRecentText(_:)), keyEquivalent: "")
                item.representedObject = text
                item.target = self
                recentMenu.addItem(item)
            }
            let recentSubmenuItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
            recentSubmenuItem.submenu = recentMenu
            menu.addItem(recentSubmenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences
        let prefItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)
        
        // Permissions
        let permItem = NSMenuItem(title: "Check System Permissions...", action: #selector(checkPermissions), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit HardyFlow", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func toggleDictation() {
        AppState.shared.toggleRecording()
    }
    
    @objc private func toggleWakeWord() {
        AppState.shared.isWakeWordEnabled.toggle()
    }
    
    @objc private func toggleAutoPaste() {
        AppState.shared.isAutoPasteEnabled.toggle()
    }
    
    @objc private func selectLocale(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppState.shared.setLocale(Locale(identifier: id))
    }
    
    @objc private func copyRecentText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow()
    }
    
    @objc private func checkPermissions() {
        PreferencesWindowController.shared.showWindow()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
