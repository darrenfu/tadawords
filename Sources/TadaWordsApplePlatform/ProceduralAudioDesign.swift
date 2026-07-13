import Foundation
import TadaWordsDomain

enum ProceduralWaveform: Hashable, Sendable {
    case sine
    case softTriangle
    case wooden
}

enum ProceduralInstrument: Hashable, Sendable {
    case harp
    case glockenspiel
    case warmPad
    case mechanicalPluck
    case bouncyBass
    case marimba
    case naturePluck
}

enum ProceduralPercussionVoice: Hashable, Sendable {
    case softKick
    case woodblock
    case brush
    case sparkle
}

struct ProceduralNoteEvent: Hashable, Sendable {
    let midiNote: Int
    let start: Double
    let duration: Double
    let gain: Double
    let pan: Double
    let instrument: ProceduralInstrument
}

struct ProceduralPercussionEvent: Hashable, Sendable {
    let start: Double
    let gain: Double
    let pan: Double
    let voice: ProceduralPercussionVoice
}

struct AmbientMusicRecipe: Hashable, Sendable {
    let duration: Double
    let notes: [ProceduralNoteEvent]
    let percussion: [ProceduralPercussionEvent]
}

struct WorldAudioPalette: Hashable, Sendable {
    let ambientPitches: [Double]
    let waveform: ProceduralWaveform
    let pulseInterval: Double
    let rootMIDINote: Int
    let scaleSemitones: [Int]

    static func palette(for world: WorldTheme) -> WorldAudioPalette {
        switch world {
        case .moonpetalKingdom:
            WorldAudioPalette(
                ambientPitches: [261.63, 329.63, 392.00, 493.88],
                waveform: .sine,
                pulseInterval: 0.75,
                rootMIDINote: 60,
                scaleSemitones: [0, 2, 4, 7, 9]
            )
        case .buildItBay:
            WorldAudioPalette(
                ambientPitches: [196.00, 246.94, 293.66, 369.99],
                waveform: .softTriangle,
                pulseInterval: 0.60,
                rootMIDINote: 55,
                scaleSemitones: [0, 2, 4, 7, 9]
            )
        case .pawsAndPines:
            WorldAudioPalette(
                ambientPitches: [293.66, 369.99, 440.00, 554.37],
                waveform: .wooden,
                pulseInterval: 0.75,
                rootMIDINote: 62,
                scaleSemitones: [0, 2, 4, 7, 9]
            )
        }
    }
}

/// Original 24-second compositions expressed as notes rather than recordings.
/// Each world has its own melody, harmony, rhythm, and instrument family.
enum ProceduralMusicComposer {
    static let loopDuration = 24.0

    static func recipe(
        for world: WorldTheme,
        emergency: Bool
    ) -> AmbientMusicRecipe {
        switch world {
        case .moonpetalKingdom:
            moonpetalRecipe(emergency: emergency)
        case .buildItBay:
            buildItRecipe(emergency: emergency)
        case .pawsAndPines:
            pawsRecipe(emergency: emergency)
        }
    }

    private static func moonpetalRecipe(emergency: Bool) -> AmbientMusicRecipe {
        let beat = 0.75
        let chords = [
            [60, 64, 67, 72],
            [57, 60, 64, 69],
            [53, 57, 60, 65],
            [55, 59, 62, 67],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.034
        )

        let arpeggios = [
            [60, 67, 72, 76, 72, 67, 64, 67],
            [57, 64, 69, 72, 69, 64, 60, 64],
            [53, 60, 65, 69, 65, 60, 57, 60],
            [55, 62, 67, 71, 67, 62, 59, 62],
        ]
        for (bar, pattern) in arpeggios.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(bar * 8) + Double(step),
                        beats: 0.82,
                        beatDuration: beat,
                        gain: 0.090,
                        pan: step.isMultiple(of: 2) ? -0.28 : 0.28,
                        instrument: .harp
                    )
                )
            }
        }

        let melody: [(Double, Int, Double)] = [
            (0.5, 76, 1.0), (2, 79, 1.0), (3.5, 81, 0.5),
            (4.5, 79, 1.0), (6, 76, 1.4),
            (8.5, 76, 0.8), (9.5, 81, 0.8), (10.5, 79, 1.0),
            (12, 76, 0.8), (13, 74, 0.8), (14, 72, 1.4),
            (16.5, 72, 0.8), (17.5, 76, 0.8), (18.5, 77, 1.0),
            (20, 76, 0.8), (21, 72, 1.4),
            (24.5, 74, 0.8), (25.5, 79, 0.8), (26.5, 83, 1.0),
            (28, 81, 0.8), (29, 79, 0.8), (30, 76, 1.5),
        ]
        notes.append(
            contentsOf: melody.map {
                note(
                    $0.1,
                    beat: $0.0,
                    beats: $0.2,
                    beatDuration: beat,
                    gain: 0.095,
                    pan: 0.10,
                    instrument: .glockenspiel
                )
            }
        )

        var percussion: [ProceduralPercussionEvent] = stride(
            from: 1.5,
            to: 32.0,
            by: 4.0
        ).map {
            percussionEvent(
                beat: $0,
                beatDuration: beat,
                gain: 0.032,
                pan: 0.40,
                voice: .sparkle
            )
        }
        if emergency {
            percussion.append(
                contentsOf: stride(from: 0.5, to: 32.0, by: 1.0).map {
                    percussionEvent(
                        beat: $0,
                        beatDuration: beat,
                        gain: 0.024,
                        pan: $0.truncatingRemainder(dividingBy: 2) < 1 ? -0.34 : 0.34,
                        voice: .brush
                    )
                }
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func buildItRecipe(emergency: Bool) -> AmbientMusicRecipe {
        let beat = 0.60
        let chords = [
            [55, 59, 62],
            [60, 64, 67],
            [52, 55, 59],
            [50, 54, 57],
            [55, 59, 62],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.022
        )
        let roots = [43, 48, 40, 38, 43]
        for (bar, root) in roots.enumerated() {
            for (offset, semitone, gain) in [
                (0.0, 0, 0.12),
                (1.5, 7, 0.085),
                (2.0, 0, 0.11),
                (3.25, 7, 0.078),
                (4.0, 0, 0.12),
                (5.5, 7, 0.085),
                (6.0, 12, 0.10),
                (7.25, 7, 0.078),
            ] {
                notes.append(
                    note(
                        root + semitone,
                        beat: Double(bar * 8) + offset,
                        beats: 0.45,
                        beatDuration: beat,
                        gain: gain,
                        pan: -0.08,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        let melody: [Int?] = [
            67, nil, 71, 74, 71, nil, 69, 67,
            72, nil, 76, 79, 76, 74, 72, nil,
            64, 67, 71, nil, 69, 67, 64, nil,
            62, 66, 69, 74, 69, nil, 66, 62,
            67, 71, 74, nil, 79, 74, 71, 67,
        ]
        for (step, midiNote) in melody.enumerated() {
            guard let midiNote else { continue }
            notes.append(
                note(
                    midiNote,
                    beat: Double(step),
                    beats: 0.48,
                    beatDuration: beat,
                    gain: 0.088,
                    pan: step.isMultiple(of: 2) ? 0.24 : -0.24,
                    instrument: .mechanicalPluck
                )
            )
        }

        var percussion: [ProceduralPercussionEvent] = []
        for beatIndex in 0..<40 {
            if beatIndex.isMultiple(of: 2) {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.095,
                        pan: -0.10,
                        voice: .softKick
                    )
                )
            }
            if beatIndex % 4 == 1 || beatIndex % 4 == 3 {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.072,
                        pan: 0.24,
                        voice: .woodblock
                    )
                )
            }
        }
        if emergency {
            percussion.append(
                contentsOf: stride(from: 0.5, to: 40.0, by: 1.0).map {
                    percussionEvent(
                        beat: $0,
                        beatDuration: beat,
                        gain: 0.030,
                        pan: $0.truncatingRemainder(dividingBy: 2) < 1 ? -0.42 : 0.42,
                        voice: .brush
                    )
                }
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func pawsRecipe(emergency: Bool) -> AmbientMusicRecipe {
        let beat = 0.75
        let chords = [
            [50, 54, 57, 62],
            [55, 59, 62, 67],
            [47, 50, 54, 59],
            [45, 49, 52, 57],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.030
        )
        let arpeggios = [
            [62, 66, 69, 74, 69, 66, 64, 66],
            [67, 71, 74, 79, 74, 71, 69, 71],
            [59, 62, 66, 71, 66, 62, 61, 62],
            [57, 61, 64, 69, 64, 61, 59, 61],
        ]
        for (bar, pattern) in arpeggios.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(bar * 8) + Double(step),
                        beats: 0.62,
                        beatDuration: beat,
                        gain: 0.078,
                        pan: step.isMultiple(of: 2) ? -0.30 : 0.30,
                        instrument: .naturePluck
                    )
                )
            }
        }

        let melody: [(Double, Int, Double)] = [
            (0, 74, 0.8), (1, 78, 0.8), (2, 81, 1.5),
            (4, 78, 0.8), (5, 76, 0.8), (6, 74, 1.4),
            (8, 79, 0.8), (9, 83, 0.8), (10, 81, 1.5),
            (12, 79, 0.8), (13, 76, 0.8), (14, 74, 1.4),
            (16, 71, 0.8), (17, 74, 0.8), (18, 78, 1.5),
            (20, 76, 0.8), (21, 74, 0.8), (22, 71, 1.4),
            (24, 73, 0.8), (25, 76, 0.8), (26, 81, 1.2),
            (28, 79, 0.8), (29, 78, 0.8), (30, 74, 1.5),
        ]
        notes.append(
            contentsOf: melody.map {
                note(
                    $0.1,
                    beat: $0.0,
                    beats: $0.2,
                    beatDuration: beat,
                    gain: 0.082,
                    pan: 0.12,
                    instrument: .marimba
                )
            }
        )
        for (beatOffset, pan) in [(6.6, -0.52), (14.4, 0.50), (22.3, -0.44)] {
            notes.append(
                note(
                    86,
                    beat: beatOffset,
                    beats: 0.22,
                    beatDuration: beat,
                    gain: 0.045,
                    pan: pan,
                    instrument: .naturePluck
                )
            )
            notes.append(
                note(
                    90,
                    beat: beatOffset + 0.28,
                    beats: 0.18,
                    beatDuration: beat,
                    gain: 0.038,
                    pan: pan * 0.82,
                    instrument: .naturePluck
                )
            )
        }

        var percussion: [ProceduralPercussionEvent] = stride(
            from: 2.0,
            to: 32.0,
            by: 4.0
        ).map {
            percussionEvent(
                beat: $0,
                beatDuration: beat,
                gain: 0.052,
                pan: -0.16,
                voice: .softKick
            )
        }
        percussion.append(
            contentsOf: stride(from: 1.0, to: 32.0, by: 2.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.038,
                    pan: 0.28,
                    voice: .woodblock
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: stride(from: 0.5, to: 32.0, by: 1.0).map {
                    percussionEvent(
                        beat: $0,
                        beatDuration: beat,
                        gain: 0.024,
                        pan: $0.truncatingRemainder(dividingBy: 2) < 1 ? -0.36 : 0.36,
                        voice: .brush
                    )
                }
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func chordBed(
        chords: [[Int]],
        beatsPerChord: Double,
        beat: Double,
        instrument: ProceduralInstrument,
        gain: Double
    ) -> [ProceduralNoteEvent] {
        chords.enumerated().flatMap { chordIndex, chord in
            chord.map { midiNote in
                note(
                    midiNote,
                    beat: Double(chordIndex) * beatsPerChord,
                    beats: beatsPerChord - 0.10,
                    beatDuration: beat,
                    gain: gain,
                    pan: Double(midiNote % 5 - 2) * 0.13,
                    instrument: instrument
                )
            }
        }
    }

    private static func note(
        _ midiNote: Int,
        beat: Double,
        beats: Double,
        beatDuration: Double,
        gain: Double,
        pan: Double,
        instrument: ProceduralInstrument
    ) -> ProceduralNoteEvent {
        ProceduralNoteEvent(
            midiNote: midiNote,
            start: beat * beatDuration,
            duration: beats * beatDuration,
            gain: gain,
            pan: pan,
            instrument: instrument
        )
    }

    private static func percussionEvent(
        beat: Double,
        beatDuration: Double,
        gain: Double,
        pan: Double,
        voice: ProceduralPercussionVoice
    ) -> ProceduralPercussionEvent {
        ProceduralPercussionEvent(
            start: beat * beatDuration,
            gain: gain,
            pan: pan,
            voice: voice
        )
    }
}
