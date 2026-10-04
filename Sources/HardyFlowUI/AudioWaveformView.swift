import SwiftUI
import HardyFlowCore

/// High-performance animated waveform visualizer reacting in real-time to microphone RMS power.
public struct AudioWaveformView: View {
    public var audioLevel: Float
    public var barCount: Int = 15
    
    // Waveform phase multipliers for dynamic organic movement (peaks in center)
    private let barMultipliers: [CGFloat] = [
        0.2, 0.35, 0.5, 0.7, 0.9, 1.2, 1.5, 1.8, 1.5, 1.2, 0.9, 0.7, 0.5, 0.35, 0.2
    ]
    
    public init(audioLevel: Float, barCount: Int = 15) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }
    
    public var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<barCount, id: \.self) { index in
                let multiplier = index < barMultipliers.count ? barMultipliers[index] : 0.8
                let rawHeight = CGFloat(audioLevel) * 26.0 * multiplier
                let clampedHeight = max(4.0, min(28.0, rawHeight))
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.75, blue: 1.0),
                                Color(red: 0.65, green: 0.38, blue: 1.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3.5, height: clampedHeight)
                    .shadow(color: Color.blue.opacity(0.35), radius: 2)
                    .animation(.spring(response: 0.15, dampingFraction: 0.65), value: clampedHeight)
            }
        }
        .frame(height: 30)
    }
}
