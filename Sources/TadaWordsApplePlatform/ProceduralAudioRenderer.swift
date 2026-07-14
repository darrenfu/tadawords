@preconcurrency import AVFoundation
import Foundation
import TadaWordsDomain

enum ProceduralAudioFactory {
    static let ambientTargetPeak: Float = 0.40
    static let writingTargetPeak: Float = 0.16

    static func launchSignature(
        world: WorldTheme?,
        sampleRate: Double
    ) -> AVAudioPCMBuffer {
        var notes: [(Double, Double, Double)] = [
            (440.00, 0.02, 0.24),
            (554.37, 0.19, 0.25),
            (659.25, 0.37, 0.27),
            (880.00, 0.58, 0.38),
            (1_318.51, 0.94, 0.18),
        ]
        if let world {
            notes.append(
                (
                    WorldAudioPalette.palette(for: world).ambientPitches[1] * 2,
                    0.78,
                    0.22
                )
            )
        }
        return makeSimpleBuffer(
            duration: 1.20,
            sampleRate: sampleRate,
            notes: notes,
            waveform: .sine,
            gain: 0.31
        )
    }

    static func ambientLoop(
        world: WorldTheme,
        sampleRate: Double,
        emergency: Bool = false
    ) -> AVAudioPCMBuffer {
        render(
            recipe: ProceduralMusicComposer.recipe(
                for: world,
                emergency: emergency
            ),
            sampleRate: sampleRate
        )
    }

    static func effect(
        cue: FunctionalAudioCue,
        world: WorldTheme,
        sampleRate: Double
    ) -> AVAudioPCMBuffer {
        let palette = WorldAudioPalette.palette(for: world)
        let tonic = palette.rootMIDINote
        let recipe:
            (
                duration: Double,
                notes: [(Double, Double, Double)],
                gain: Double
            )
        switch cue {
        case .click:
            recipe = (
                0.10,
                [(frequency(forMIDINote: tonic + 12), 0, 0.07)],
                0.18
            )
        case .correct:
            recipe = (
                0.58,
                [
                    (frequency(forMIDINote: tonic + 12), 0, 0.17),
                    (frequency(forMIDINote: tonic + 16), 0.12, 0.18),
                    (frequency(forMIDINote: tonic + 19), 0.25, 0.20),
                    (frequency(forMIDINote: tonic + 24), 0.39, 0.18),
                ],
                0.34
            )
        case .validRetry:
            recipe = (
                0.42,
                [
                    (frequency(forMIDINote: tonic + 14), 0, 0.16),
                    (frequency(forMIDINote: tonic + 12), 0.19, 0.19),
                ],
                0.17
            )
        case .technicalRetry:
            recipe = (0.30, [(330, 0, 0.08), (330, 0.16, 0.08)], 0.14)
        case .star(let index):
            let step = max(0, min(2, index))
            let scaleDegree = palette.scaleSemitones[step + 1]
            let starNote = tonic + 12 + scaleDegree
            recipe = (
                0.38,
                [
                    (frequency(forMIDINote: starNote), 0, 0.24),
                    (frequency(forMIDINote: starNote + 7), 0.13, 0.21),
                ],
                0.30
            )
        case .reward:
            recipe = (
                1.04,
                [
                    (frequency(forMIDINote: tonic + 12), 0, 0.22),
                    (frequency(forMIDINote: tonic + 16), 0.15, 0.24),
                    (frequency(forMIDINote: tonic + 19), 0.31, 0.27),
                    (frequency(forMIDINote: tonic + 24), 0.50, 0.36),
                    (frequency(forMIDINote: tonic + 28), 0.74, 0.26),
                ],
                0.34
            )
        case .writing(let tool):
            return writingEffect(tool: tool, sampleRate: sampleRate)
        }
        return makeSimpleBuffer(
            duration: recipe.duration,
            sampleRate: sampleRate,
            notes: recipe.notes,
            waveform: palette.waveform,
            gain: recipe.gain
        )
    }

    /// A tiny, voice-safe texture for one accepted handwriting-move sample.
    /// The playback service spaces these buffers so they feel continuous while
    /// a child draws without ever building a queue of stale stroke sounds.
    static func writingEffect(
        tool: HandwritingTool,
        sampleRate: Double
    ) -> AVAudioPCMBuffer {
        let duration: Double
        let gain: Double
        switch tool {
        case .pencil:
            duration = 0.045
            gain = 0.075
        case .crayon:
            duration = 0.060
            gain = 0.105
        case .chalk:
            duration = 0.050
            gain = 0.080
        case .brush:
            duration = 0.070
            gain = 0.110
        }

        let buffer = emptyStereoBuffer(duration: duration, sampleRate: sampleRate)
        guard let channels = buffer.floatChannelData else { return buffer }
        let frameCount = Int(buffer.frameLength)
        var previousNoise = (left: 0.0, right: 0.0)
        var smoothedNoise = (left: 0.0, right: 0.0)

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let progress = Double(frame) / Double(max(1, frameCount - 1))
            let attack = min(1, time / 0.002)
            let release = min(1, max(0, duration - time) / 0.009)
            let envelope = attack * release
            let noise = (
                left: deterministicNoise(frame: frame),
                right: deterministicNoise(frame: frame &+ 7_919)
            )
            smoothedNoise.left = smoothedNoise.left * 0.82 + noise.left * 0.18
            smoothedNoise.right = smoothedNoise.right * 0.82 + noise.right * 0.18

            let texture: (left: Double, right: Double)
            switch tool {
            case .pencil:
                let graphiteTone = sin(2 * Double.pi * (1_340 + 180 * progress) * time)
                texture = (
                    (noise.left - previousNoise.left * 0.68) * 0.72
                        + graphiteTone * 0.09,
                    (noise.right - previousNoise.right * 0.68) * 0.72
                        + graphiteTone * 0.09
                )
            case .crayon:
                let waxTone = softTriangle(2 * Double.pi * 118 * time)
                texture = (
                    noise.left * 0.34 + smoothedNoise.left * 0.54 + waxTone * 0.24,
                    noise.right * 0.34 + smoothedNoise.right * 0.54 + waxTone * 0.24
                )
            case .chalk:
                let dustPulse = frame % 29 < 11 ? 1.0 : 0.32
                let brittleTone = sin(2 * Double.pi * 3_180 * time)
                texture = (
                    (noise.left * 0.78
                        + deterministicNoise(frame: frame &+ 2_503) * 0.31)
                        * dustPulse + brittleTone * 0.10,
                    (noise.right * 0.78
                        + deterministicNoise(frame: frame &+ 5_009) * 0.31)
                        * dustPulse + brittleTone * 0.10
                )
            case .brush:
                let bristleTone = sin(2 * Double.pi * 214 * time)
                texture = (
                    smoothedNoise.left * 0.92 + bristleTone * 0.08,
                    smoothedNoise.right * 0.92 + bristleTone * 0.08
                )
            }

            channels[0][frame] = Float(texture.left * envelope * gain)
            channels[1][frame] = Float(texture.right * envelope * gain)
            previousNoise = noise
        }
        hardLimit(
            channels: channels,
            frameCount: frameCount,
            limit: writingTargetPeak
        )
        return buffer
    }

    private static func render(
        recipe: AmbientMusicRecipe,
        sampleRate: Double
    ) -> AVAudioPCMBuffer {
        let buffer = emptyStereoBuffer(
            duration: recipe.duration,
            sampleRate: sampleRate
        )
        guard let channels = buffer.floatChannelData else { return buffer }

        for event in recipe.notes {
            render(
                note: event,
                into: channels,
                frameCount: Int(buffer.frameLength),
                sampleRate: sampleRate
            )
        }
        for event in recipe.percussion {
            render(
                percussion: event,
                into: channels,
                frameCount: Int(buffer.frameLength),
                sampleRate: sampleRate
            )
        }
        normalize(
            channels: channels,
            frameCount: Int(buffer.frameLength),
            targetPeak: ambientTargetPeak
        )
        return buffer
    }

    private static func render(
        note: ProceduralNoteEvent,
        into channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        sampleRate: Double
    ) {
        let startFrame = max(0, Int(note.start * sampleRate))
        let endFrame = min(
            frameCount,
            Int((note.start + note.duration) * sampleRate)
        )
        guard endFrame > startFrame else { return }
        let pitch = frequency(forMIDINote: note.midiNote)
        let pan = stereoGains(for: note.pan)

        for frame in startFrame..<endFrame {
            let localTime = Double(frame - startFrame) / sampleRate
            let envelope = noteEnvelope(
                time: localTime,
                duration: note.duration,
                instrument: note.instrument
            )
            let sample =
                instrumentSample(
                    pitch: pitch,
                    time: localTime,
                    instrument: note.instrument
                ) * envelope * note.gain
            channels[0][frame] += Float(sample * pan.left)
            channels[1][frame] += Float(sample * pan.right)
        }
    }

    private static func render(
        percussion: ProceduralPercussionEvent,
        into channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        sampleRate: Double
    ) {
        let duration = percussionDuration(percussion.voice)
        let startFrame = max(0, Int(percussion.start * sampleRate))
        let endFrame = min(frameCount, Int((percussion.start + duration) * sampleRate))
        guard endFrame > startFrame else { return }
        let pan = stereoGains(for: percussion.pan)

        for frame in startFrame..<endFrame {
            let localFrame = frame - startFrame
            let time = Double(localFrame) / sampleRate
            let progress = min(1, time / duration)
            let sample =
                percussionSample(
                    voice: percussion.voice,
                    time: time,
                    progress: progress,
                    frame: localFrame
                ) * percussion.gain
            channels[0][frame] += Float(sample * pan.left)
            channels[1][frame] += Float(sample * pan.right)
        }
    }

    private static func instrumentSample(
        pitch: Double,
        time: Double,
        instrument: ProceduralInstrument
    ) -> Double {
        let phase = 2 * Double.pi * pitch * time
        switch instrument {
        case .harp:
            return sin(phase) * 0.72 + sin(phase * 2.01) * 0.18
                + sin(phase * 3.00) * 0.07
        case .glockenspiel:
            return sin(phase) * 0.58 + sin(phase * 2.76) * 0.23
                + sin(phase * 5.41) * 0.10
        case .warmPad:
            let movement = 0.92 + 0.08 * sin(2 * Double.pi * 0.18 * time)
            return
                (sin(phase * 0.997) * 0.38 + sin(phase * 1.003) * 0.38
                + sin(phase * 2) * 0.10) * movement
        case .mechanicalPluck:
            return softTriangle(phase) * 0.72 + sin(phase * 2) * 0.14
                + sin(phase * 4) * 0.05
        case .bouncyBass:
            return sin(phase) * 0.70 + softTriangle(phase) * 0.24
        case .marimba:
            return sin(phase) * 0.68 + sin(phase * 3.98) * 0.18
                + sin(phase * 9.15) * 0.05
        case .naturePluck:
            return sin(phase) * 0.65 + sin(phase * 2.02) * 0.16
                + sin(phase * 3.99) * 0.08
        }
    }

    private static func noteEnvelope(
        time: Double,
        duration: Double,
        instrument: ProceduralInstrument
    ) -> Double {
        let safeDuration = max(0.001, duration)
        let remaining = max(0, safeDuration - time)
        switch instrument {
        case .warmPad:
            return min(1, time / 0.38) * min(1, remaining / 0.48) * 0.88
        case .glockenspiel:
            return min(1, time / 0.004) * pow(max(0, 1 - time / safeDuration), 2.25)
        case .harp:
            return min(1, time / 0.008) * pow(max(0, 1 - time / safeDuration), 1.65)
        case .mechanicalPluck:
            return min(1, time / 0.005) * pow(max(0, 1 - time / safeDuration), 2.6)
        case .bouncyBass:
            return min(1, time / 0.010) * pow(max(0, 1 - time / safeDuration), 1.45)
        case .marimba:
            return min(1, time / 0.006) * pow(max(0, 1 - time / safeDuration), 2.1)
        case .naturePluck:
            return min(1, time / 0.007) * pow(max(0, 1 - time / safeDuration), 2.0)
        }
    }

    private static func percussionSample(
        voice: ProceduralPercussionVoice,
        time: Double,
        progress: Double,
        frame: Int
    ) -> Double {
        switch voice {
        case .softKick:
            let phase = 2 * Double.pi * (96 * time - 28 * time * time)
            return sin(phase) * pow(max(0, 1 - progress), 2.4)
        case .woodblock:
            let envelope = pow(max(0, 1 - progress), 3.8)
            return
                (sin(2 * Double.pi * 720 * time) * 0.72
                + sin(2 * Double.pi * 1_080 * time) * 0.22) * envelope
        case .brush:
            return deterministicNoise(frame: frame) * pow(max(0, 1 - progress), 2.1)
        case .sparkle:
            let envelope = pow(max(0, 1 - progress), 2.5)
            return
                (sin(2 * Double.pi * 1_420 * time) * 0.55
                + sin(2 * Double.pi * 2_130 * time) * 0.30) * envelope
        }
    }

    private static func percussionDuration(_ voice: ProceduralPercussionVoice) -> Double {
        switch voice {
        case .softKick: 0.22
        case .woodblock: 0.13
        case .brush: 0.10
        case .sparkle: 0.28
        }
    }

    private static func makeSimpleBuffer(
        duration: Double,
        sampleRate: Double,
        notes: [(pitch: Double, start: Double, duration: Double)],
        waveform: ProceduralWaveform,
        gain: Double
    ) -> AVAudioPCMBuffer {
        let buffer = emptyStereoBuffer(duration: duration, sampleRate: sampleRate)
        guard let channels = buffer.floatChannelData else { return buffer }
        for note in notes {
            let startFrame = max(0, Int(note.start * sampleRate))
            let endFrame = min(
                Int(buffer.frameLength),
                Int((note.start + note.duration) * sampleRate)
            )
            guard endFrame > startFrame else { continue }
            for frame in startFrame..<endFrame {
                let localTime = Double(frame - startFrame) / sampleRate
                let progress = localTime / note.duration
                let attack = min(1, localTime / 0.018)
                let decay = pow(
                    max(0, 1 - progress),
                    waveform == .softTriangle ? 2.8 : 1.8
                )
                let value =
                    oscillator(
                        phase: 2 * Double.pi * note.pitch * localTime,
                        waveform: waveform
                    ) * attack * decay * gain * 0.707
                channels[0][frame] += Float(value)
                channels[1][frame] += Float(value)
            }
        }
        hardLimit(channels: channels, frameCount: Int(buffer.frameLength))
        return buffer
    }

    private static func emptyStereoBuffer(
        duration: Double,
        sampleRate: Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        )!
        buffer.frameLength = frameCount
        return buffer
    }

    private static func normalize(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        targetPeak: Float
    ) {
        var peak: Float = 0
        for channelIndex in 0..<2 {
            for frame in 0..<frameCount {
                peak = max(peak, abs(channels[channelIndex][frame]))
            }
        }
        guard peak > 0 else { return }
        let scale = targetPeak / peak
        for channelIndex in 0..<2 {
            for frame in 0..<frameCount {
                channels[channelIndex][frame] *= scale
            }
        }
    }

    private static func hardLimit(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        limit: Float = 0.72
    ) {
        for channelIndex in 0..<2 {
            for frame in 0..<frameCount {
                channels[channelIndex][frame] = max(
                    -limit,
                    min(limit, channels[channelIndex][frame])
                )
            }
        }
    }

    private static func stereoGains(for pan: Double) -> (left: Double, right: Double) {
        let clamped = max(-1, min(1, pan))
        return (
            sqrt((1 - clamped) * 0.5),
            sqrt((1 + clamped) * 0.5)
        )
    }

    private static func frequency(forMIDINote midiNote: Int) -> Double {
        440 * pow(2, Double(midiNote - 69) / 12)
    }

    private static func softTriangle(_ phase: Double) -> Double {
        (2 / Double.pi) * asin(sin(phase))
    }

    private static func oscillator(
        phase: Double,
        waveform: ProceduralWaveform
    ) -> Double {
        switch waveform {
        case .sine:
            sin(phase)
        case .softTriangle:
            softTriangle(phase) * 0.78 + sin(phase * 2) * 0.08
        case .wooden:
            sin(phase) * 0.72 + sin(phase * 2.01) * 0.18
                + sin(phase * 3.98) * 0.06
        }
    }

    private static func deterministicNoise(frame: Int) -> Double {
        var value = UInt32(truncatingIfNeeded: frame &* 1_664_525 &+ 1_013_904_223)
        value ^= value << 13
        value ^= value >> 17
        value ^= value << 5
        return Double(value) / Double(UInt32.max) * 2 - 1
    }
}
