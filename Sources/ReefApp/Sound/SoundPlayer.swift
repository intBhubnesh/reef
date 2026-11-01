import AVFoundation
import ReefCore

/// Plays the short UI effects bundled from the user's Audio collection. The synthesized motif
/// remains a fallback so a damaged or incomplete app bundle never makes alerts fully silent.
@MainActor
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]
    private var attached = false

    func play(_ kind: SoundKind) {
        guard let buffer = buffer(for: kind) else { return }
        if !attached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            player.volume = 0.45
            attached = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                Log.warn("sound", "engine failed to start", ["error": "\(error)"])
                return
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func buffer(for kind: SoundKind) -> AVAudioPCMBuffer? {
        if let cached = buffers[kind] { return cached }
        let rendered = bundledBuffer(for: kind) ?? ToneSynth.render(kind: kind)
        buffers[kind] = rendered
        return rendered
    }

    private func bundledBuffer(for kind: SoundKind) -> AVAudioPCMBuffer? {
        guard let name = Self.resourceNames[kind],
              let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
        else {
            Log.warn("sound", "asset missing", ["kind": kind.rawValue])
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            Log.warn("sound", "asset failed to load", ["kind": kind.rawValue, "error": "\(error)"])
            return nil
        }
    }

    private static let resourceNames: [SoundKind: String] = [
        .started: "started",
        .actionCompleted: "action-completed",
        .inputNeeded: "input-needed",
        .done: "done",
        .failed: "failed"
    ]
}
