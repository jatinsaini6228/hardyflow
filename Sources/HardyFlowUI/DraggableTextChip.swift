import SwiftUI
import AppKit
import HardyFlowCore

/// Draggable text chip supporting macOS native Drag & Drop into any external window or text field.
public struct DraggableTextChip: View {
    public let text: String
    @ObservedObject public var state: AppState = AppState.shared
    
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.cyan)
            
            Text("Drag text to any app")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(state.isChipHovered ? Color.cyan.opacity(0.25) : Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(state.isChipHovered ? Color.cyan.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                state.isChipHovered = hovering
            }
        }
        .onDrag {
            NSItemProvider(object: text as NSString)
        }
        .help("Click and drag this badge into any background application window, document, or text field.")
    }
}
