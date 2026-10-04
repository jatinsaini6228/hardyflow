import Foundation
import AppKit
import Carbon

/// Registers and manages global system-wide hotkeys using Carbon EventHotKey API.
/// Supports both Tap-to-Toggle and Push-to-Talk (Hold-to-Talk), plus Re-Paste Last Dictation (Option + Shift + V).
public final class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()
    
    public var onHotkeyPressed: (() -> Void)?
    public var onPushToTalkFinished: (() -> Void)?
    public var onRePastePressed: (() -> Void)?
    
    private var primaryHotKeyRef: EventHotKeyRef?
    private var rePasteHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    private var primaryKeyDownTime: Double = 0.0
    
    private init() {}
    
    /// Registers the default shortcuts:
    /// - Primary (Option + Space): Tap-to-Talk or Push-to-Talk
    /// - Re-Paste (Option + Shift + V): Instant re-paste of last dictation
    public func registerDefaultHotkey() {
        registerHotkeys(
            primaryKeyCode: UInt32(kVK_Space),
            primaryModifiers: UInt32(optionKey),
            rePasteKeyCode: UInt32(0x09), // kVK_ANSI_V
            rePasteModifiers: UInt32(optionKey | shiftKey)
        )
    }
    
    /// Registers custom global hotkeys with Carbon.
    public func registerHotkeys(
        primaryKeyCode: UInt32,
        primaryModifiers: UInt32,
        rePasteKeyCode: UInt32,
        rePasteModifiers: UInt32
    ) {
        unregisterHotkeys()
        
        var primaryID = EventHotKeyID()
        primaryID.signature = OSType(0x48524459) // 'HRDY'
        primaryID.id = 1
        
        var rePasteID = EventHotKeyID()
        rePasteID.signature = OSType(0x48524459) // 'HRDY'
        rePasteID.id = 2
        
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        
        let handlerBlock: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            let eventKind = GetEventKind(event)
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            guard status == noErr else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            if hotKeyID.id == 1 {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    manager.handlePrimaryKeyDown()
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    manager.handlePrimaryKeyUp()
                }
            } else if hotKeyID.id == 2 {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    manager.handleRePasteKeyDown()
                }
            }
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )
        
        if installStatus != noErr {
            print("⚠️ [HotkeyManager] Failed to install Carbon event handler: \(installStatus)")
            return
        }
        
        // Register Primary (Option + Space)
        let primaryStatus = RegisterEventHotKey(
            primaryKeyCode,
            primaryModifiers,
            primaryID,
            GetApplicationEventTarget(),
            0,
            &primaryHotKeyRef
        )
        if primaryStatus != noErr {
            print("⚠️ [HotkeyManager] Failed to register primary hotkey (Status: \(primaryStatus))")
        } else {
            print("✅ [HotkeyManager] Primary hotkey registered: Option + Space (Tap-to-Toggle & Push-to-Talk).")
        }
        
        // Register Re-Paste (Option + Shift + V)
        let rePasteStatus = RegisterEventHotKey(
            rePasteKeyCode,
            rePasteModifiers,
            rePasteID,
            GetApplicationEventTarget(),
            0,
            &rePasteHotKeyRef
        )
        if rePasteStatus != noErr {
            print("⚠️ [HotkeyManager] Failed to register re-paste hotkey (Status: \(rePasteStatus))")
        } else {
            print("✅ [HotkeyManager] Re-paste hotkey registered: Option + Shift + V.")
        }
    }
    
    private func handlePrimaryKeyDown() {
        primaryKeyDownTime = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyPressed?()
        }
    }
    
    private func handlePrimaryKeyUp() {
        let duration = CACurrentMediaTime() - primaryKeyDownTime
        // If held down for 400ms or longer, user was using Push-to-Talk (Hold-to-Talk)
        if duration >= 0.4 {
            DispatchQueue.main.async { [weak self] in
                print("🎙️ [HotkeyManager] Push-to-talk release detected (held for \(String(format: "%.2f", duration))s). Auto-finishing.")
                self?.onPushToTalkFinished?()
            }
        }
    }
    
    private func handleRePasteKeyDown() {
        DispatchQueue.main.async { [weak self] in
            print("📋 [HotkeyManager] Re-paste hotkey triggered (Option + Shift + V).")
            self?.onRePastePressed?()
        }
    }
    
    /// Unregisters all registered hotkeys.
    public func unregisterHotkeys() {
        if let primary = primaryHotKeyRef {
            UnregisterEventHotKey(primary)
            primaryHotKeyRef = nil
        }
        if let rePaste = rePasteHotKeyRef {
            UnregisterEventHotKey(rePaste)
            rePasteHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    public func unregisterHotkey() {
        unregisterHotkeys()
    }
    
    deinit {
        unregisterHotkeys()
    }
}
