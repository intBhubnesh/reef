import AVFoundation
import ReefCore

/// Three tiny square-wave motifs rendered at 44.1 kHz; no bundled audio files.
enum ToneSynth {
    static let sampleRate: Double = 44_100

    struct Note { let frequency: Double; let duration: Double }

    static func motif(_ kind: SoundKind) -> [Note] {
        switch kind {
        case .inputNeeded: return [Note(frequency: 660, duration: 0.09), Note(frequency: 880, duration: 0.09)]
        case .done: return [Note(frequency: 523, duration: 0.08), Note(frequency: 659, duration: 0.08), Note(frequency: 784, duration: 0.08)]
        case .failed: return [Note(frequency: 330, duration: 0.12), Note(frequency: 220, duration: 0.12)]
        }
    }

    static func render(kind: SoundKind, volume: Float = 0.25) -> AVAudioPCMBuffer? {
        let notes = motif(kind)
        let gap = 0.02
        let total = notes.reduce(0) { $0 + $1.duration + gap }
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var cursor = 0
        let ramp = Int(0.005 * sampleRate)
        for note in notes {
            let count = Int(note.duration * sampleRate)
            for i in 0..<count where cursor + i < Int(frames) {
                let t = Double(i) / sampleRate
                let square: Float = sin(2 * .pi * note.frequency * t) >= 0 ? 1 : -1
                var envelope: Float = 1
                if i < ramp { envelope = Float(i) / Float(ramp) }
                if count - i < ramp { envelope = min(envelope, Float(count - i) / Float(ramp)) }
                channel[cursor + i] = square * envelope * volume
            }
            cursor += count + Int(gap * sampleRate)
        }
        return buffer
    }
}
