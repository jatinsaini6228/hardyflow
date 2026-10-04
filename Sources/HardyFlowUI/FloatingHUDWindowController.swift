import Foundation
import AppKit
import SwiftUI
import Combine
import HardyFlowCore

/// Custom NSPanel subclass that allows the borderless floating panel to become key
/// so that text fields, TextEditor, and keyboard shortcuts can be interacted with directly.
public final class HUDPanel: NSPanel {
    public override var canBecomeKey: Bool {
        return true
    }
    public override var canBecomeMain: Bool {
        return true
    }
}

/// Controls the resizable, draggable floating NSPanel presenting the HardyFlow HUD overlay above all spaces.
public final class FloatingHUDWindowController: NSWindowController, NSWindowDelegate, @unchecked Sendable {
    public static let shared = FloatingHUDWindowController()
    
    private var cancellables = Set<AnyCancellable>()
    public private(set) var hudPanel: HUDPanel?
    private var hasUserPositioned: Bool = false
    
    private init() {
        super.init(window: nil)
        setupPanel()
        bindAppState()
        setupNotificationObservers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPanel() {
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // Shadow is rendered inside SwiftUI view
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.ignoresMouseEvents = false
        panel.minSize = NSSize(width: 420, height: 180)
        panel.maxSize = NSSize(width: 850, height: 600)
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: FloatingHUDView())
        panel.contentView = hostingView
        
        self.hudPanel = panel
        self.window = panel
        
        repositionWindow()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HardyFlowHideHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideHUD(immediate: true)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WisperflowHideHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideHUD(immediate: true)
        }
    }
    
    private func bindAppState() {
        AppState.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .recording:
                    self.showHUD()
                case .finishing:
                    // Dismiss immediately during paste so target app regains key window focus instantly
                    self.hideHUD(immediate: true)
                case .idle, .listeningWakeWord:
                    self.hideHUD()
                }
            }
            .store(in: &cancellables)
    }
    
    public func showHUD() {
        guard let panel = hudPanel else { return }
        AppState.shared.refreshPermissions()
        if !hasUserPositioned {
            repositionWindow()
        }
        
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
    
    public func hideHUD(immediate: Bool = false) {
        guard let panel = hudPanel, panel.isVisible else { return }
        
        if immediate {
            panel.orderOut(nil)
            panel.alphaValue = 0.0
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    public func repositionWindow() {
        guard let panel = hudPanel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        let screenRect = screen.visibleFrame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 200
        
        // Position centered horizontally, 90 points above bottom edge
        let posX = screenRect.origin.x + (screenRect.width - panelWidth) / 2.0
        let posY = screenRect.origin.y + 90.0
        
        panel.setFrame(NSRect(x: posX, y: posY, width: panelWidth, height: panelHeight), display: true)
    }
    
    public func resizeWindow(by delta: CGSize) {
        guard let panel = hudPanel else { return }
        hasUserPositioned = true
        var currentFrame = panel.frame
        let newWidth = max(panel.minSize.width, min(panel.maxSize.width, currentFrame.width + delta.width))
        let newHeight = max(panel.minSize.height, min(panel.maxSize.height, currentFrame.height - delta.height))
        
        currentFrame.origin.y += (currentFrame.height - newHeight)
        currentFrame.size.width = newWidth
        currentFrame.size.height = newHeight
        
        panel.setFrame(currentFrame, display: true, animate: false)
    }
    
    // MARK: - NSWindowDelegate
    public func windowDidMove(_ notification: Notification) {
        hasUserPositioned = true
    }
    
    public func windowDidResize(_ notification: Notification) {
        hasUserPositioned = true
    }
}
