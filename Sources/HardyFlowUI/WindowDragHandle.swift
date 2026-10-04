import SwiftUI
import AppKit

/// Native NSView representable that hooks into macOS window server dragging.
/// Allows clicking and dragging anywhere on the header or card to move the floating HUD across any monitor.
public struct WindowDragHandleView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        return view
    }
    
    public func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

public final class WindowDragNSView: NSView {
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    
    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

/// Native AppKit view for smooth, responsive bottom-right corner window resizing.
public struct WindowResizeHandleView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> WindowResizeNSView {
        return WindowResizeNSView()
    }
    
    public func updateNSView(_ nsView: WindowResizeNSView, context: Context) {}
}

public final class WindowResizeNSView: NSView {
    private var initialFrame: NSRect = .zero
    private var initialMouseLocation: NSPoint = .zero
    
    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        initialFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let currentMouseLocation = NSEvent.mouseLocation
        let dx = currentMouseLocation.x - initialMouseLocation.x
        let dy = currentMouseLocation.y - initialMouseLocation.y
        
        let newWidth = max(window.minSize.width, min(window.maxSize.width, initialFrame.width + dx))
        let newHeight = max(window.minSize.height, min(window.maxSize.height, initialFrame.height - dy))
        let newY = initialFrame.origin.y + initialFrame.height - newHeight
        
        let newFrame = NSRect(x: initialFrame.origin.x, y: newY, width: newWidth, height: newHeight)
        window.setFrame(newFrame, display: true, animate: false)
    }
}
