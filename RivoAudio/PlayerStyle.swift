import SwiftUI
import AVFoundation

// Shared visual language: ink background, violet surfaces and warm accents.
enum PlayerStyle {
    static let accent = Color(red: 0.83, green: 0.68, blue: 1)
    static let ink = Color(red: 0.035, green: 0.045, blue: 0.08)
    static let surface = Color(red: 0.10, green: 0.105, blue: 0.16)
}

struct PlayerBackdrop: View {
    var image: UIImage? = nil
    var body: some View {
        // The artwork must never contribute its scaled-to-fill size to the parent layout.
        GeometryReader { geometry in
            ZStack {
                PlayerStyle.ink
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().blur(radius: 65).opacity(0.38)
                }
                LinearGradient(colors: [.purple.opacity(0.30), PlayerStyle.ink.opacity(0.8), PlayerStyle.ink], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct TransportButton: View {
    let symbol: String
    let label: String
    var large = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 32 : 23, weight: .semibold))
                .foregroundStyle(large ? PlayerStyle.ink : .white)
                .frame(width: large ? 84 : 60, height: large ? 84 : 60)
                .background(large ? PlayerStyle.accent : Color.black.opacity(0.45), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

actor WaveformReader {
    static let shared = WaveformReader()
    func peaks(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024) else { return [] }
        var values: [Float] = []
        for index in 0..<56 {
            if Task.isCancelled { return [] }
            file.framePosition = min(file.length - 1, Int64(Double(index) / 56 * Double(file.length)))
            do { try file.read(into: buffer, frameCount: 1024) } catch { return [] }
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return [] }
            var sum: Float = 0
            for frame in 0..<Int(buffer.frameLength) { sum += samples[frame] * samples[frame] }
            values.append(sqrt(sum / Float(buffer.frameLength)))
        }
        let maximum = max(values.max() ?? 0, 0.001)
        return values.map { $0 / maximum }
    }
}

struct PlaybackWaveform: View {
    let peaks: [Float]
    let progress: Double
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(peaks.indices, id: \.self) { index in
                    Capsule().fill(Double(index) / Double(max(1, peaks.count)) <= progress ? PlayerStyle.accent : .white.opacity(0.18))
                        .frame(height: max(4, CGFloat(peaks[index]) * geometry.size.height))
                }
            }.frame(height: geometry.size.height)
        }.frame(height: 46).accessibilityHidden(true)
    }
}
