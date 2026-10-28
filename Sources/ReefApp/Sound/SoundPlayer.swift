import AVFoundation
import ReefCore

/// Plays the built-in tones through a lazily started audio engine.
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
        let rendered = ToneSynth.render(kind: kind)
        buffers[kind] = rendered
        return rendered
    }
}
