import Foundation
import TadaWordsDomain

enum ProceduralWaveform: Hashable, Sendable {
    case sine
    case softTriangle
    case wooden
    case marimba
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
                pulseInterval: 0.60,
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
        case .dinoDiscovery:
            WorldAudioPalette(
                ambientPitches: [164.81, 220.00, 261.63, 329.63],
                waveform: .wooden,
                pulseInterval: 0.75,
                rootMIDINote: 52,
                scaleSemitones: [0, 3, 5, 7, 10]
            )
        case .firehouseHeroes:
            WorldAudioPalette(
                ambientPitches: [220.00, 277.18, 329.63, 440.00],
                waveform: .softTriangle,
                pulseInterval: 0.50,
                rootMIDINote: 57,
                scaleSemitones: [0, 2, 4, 7, 11]
            )
        case .brickworkCity:
            WorldAudioPalette(
                ambientPitches: [246.94, 311.13, 369.99, 493.88],
                waveform: .wooden,
                pulseInterval: 0.50,
                rootMIDINote: 59,
                scaleSemitones: [0, 2, 5, 7, 10]
            )
        case .frostlightWorld:
            WorldAudioPalette(
                ambientPitches: [329.63, 415.30, 493.88, 659.25],
                waveform: .sine,
                pulseInterval: 0.80,
                rootMIDINote: 64,
                scaleSemitones: [0, 2, 4, 7, 11]
            )
        case .coasterCarnival:
            WorldAudioPalette(
                ambientPitches: [233.08, 293.66, 349.23, 466.16],
                waveform: .softTriangle,
                pulseInterval: 0.40,
                rootMIDINote: 58,
                scaleSemitones: [0, 2, 5, 7, 9]
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
        case .dinoDiscovery:
            dinoRecipe(emergency: emergency)
        case .firehouseHeroes:
            firehouseRecipe(emergency: emergency)
        case .brickworkCity:
            brickworkRecipe(emergency: emergency)
        case .frostlightWorld:
            frostlightRecipe(emergency: emergency)
        case .coasterCarnival:
            coasterRecipe(emergency: emergency)
        }
    }

    private static func moonpetalRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // Five eight-beat phrases at 100 BPM keep the 24-second loop buoyant without
        // raising playback volume. The syncopation is original to Moonpetal Kingdom.
        let beat = 0.60
        let chords = [
            [60, 64, 67, 72],
            [57, 60, 64, 69],
            [53, 57, 60, 65],
            [55, 59, 62, 67],
            [60, 64, 67, 72],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.024
        )

        let arpeggios = [
            [60, 67, 72, 76, 79, 76, 72, 67],
            [57, 64, 69, 72, 76, 72, 69, 64],
            [53, 60, 65, 69, 72, 69, 65, 60],
            [55, 62, 67, 71, 74, 71, 67, 62],
            [60, 67, 72, 76, 79, 83, 79, 76],
        ]
        for (bar, pattern) in arpeggios.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(bar * 8) + Double(step),
                        beats: 0.56,
                        beatDuration: beat,
                        gain: 0.076,
                        pan: step.isMultiple(of: 2) ? -0.30 : 0.30,
                        instrument: .harp
                    )
                )
            }
        }

        let melody: [(Double, Int, Double)] = [
            (0.5, 76, 0.7), (1.5, 79, 0.7), (2.5, 81, 0.45),
            (3.25, 79, 0.45), (4, 83, 0.8), (5.5, 79, 0.7), (6.5, 76, 1.0),
            (8.5, 76, 0.6), (9.25, 81, 0.6), (10, 79, 0.7),
            (11.5, 76, 0.6), (12.25, 74, 0.6), (13, 72, 0.9),
            (16.5, 72, 0.6), (17.25, 76, 0.6), (18, 77, 0.7),
            (19.5, 81, 0.6), (20.25, 79, 0.6), (21, 76, 0.9),
            (24.5, 74, 0.6), (25.25, 79, 0.6), (26, 83, 0.7),
            (27.5, 81, 0.6), (28.25, 79, 0.6), (29, 76, 0.9),
            (32.5, 76, 0.6), (33.25, 81, 0.6), (34, 84, 0.7),
            (35.5, 83, 0.6), (36.25, 79, 0.6), (37, 76, 0.8), (38.5, 84, 0.8),
        ]
        notes.append(
            contentsOf: melody.map {
                note(
                    $0.1,
                    beat: $0.0,
                    beats: $0.2,
                    beatDuration: beat,
                    gain: 0.082,
                    pan: $0.0.truncatingRemainder(dividingBy: 2) < 1 ? 0.16 : -0.16,
                    instrument: .glockenspiel
                )
            }
        )

        let bassRoots = [48, 45, 41, 43, 48]
        for (bar, root) in bassRoots.enumerated() {
            for beatOffset in [0.0, 2.0, 4.0, 6.0] {
                notes.append(
                    note(
                        root,
                        beat: Double(bar * 8) + beatOffset,
                        beats: 0.62,
                        beatDuration: beat,
                        gain: beatOffset.isZero ? 0.062 : 0.050,
                        pan: -0.08,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        var percussion: [ProceduralPercussionEvent] = []
        for beatIndex in 0..<40 {
            if beatIndex.isMultiple(of: 2) {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.040,
                        pan: -0.14,
                        voice: .softKick
                    )
                )
            }
            if beatIndex % 4 == 1 || beatIndex % 4 == 3 {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex) + 0.5,
                        beatDuration: beat,
                        gain: 0.025,
                        pan: beatIndex % 4 == 1 ? 0.40 : -0.40,
                        voice: .sparkle
                    )
                )
            }
        }
        percussion.append(
            contentsOf: stride(from: 0.5, to: 39.5, by: 1.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.010,
                    pan: $0.truncatingRemainder(dividingBy: 2) < 1 ? -0.46 : 0.46,
                    voice: .brush
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: stride(from: 0.25, to: 39.75, by: 0.5).map {
                    percussionEvent(
                        beat: $0,
                        beatDuration: beat,
                        gain: 0.016,
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

    private static func dinoRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // A relaxed 80 BPM jungle groove uses low, rounded notes for dinosaur
        // footsteps while the marimba melody keeps the score playful, not scary.
        let beat = 0.75
        let chords = [
            [40, 43, 47, 52],
            [38, 42, 45, 50],
            [43, 47, 50, 55],
            [36, 40, 43, 48],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.026
        )
        let bassRoots = [40, 38, 43, 36]
        for (bar, root) in bassRoots.enumerated() {
            for offset in [0.0, 3.0, 4.0, 6.5] {
                notes.append(
                    note(
                        root,
                        beat: Double(bar * 8) + offset,
                        beats: offset == 0 ? 0.90 : 0.55,
                        beatDuration: beat,
                        gain: offset == 0 ? 0.105 : 0.072,
                        pan: -0.12,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        let melody: [Int?] = [
            64, nil, 67, 64, 62, 59, nil, 62,
            62, 66, 69, nil, 66, 62, 57, nil,
            67, nil, 71, 74, 71, 67, 62, nil,
            60, 64, 67, 72, 67, nil, 64, 60,
        ]
        for (step, midiNote) in melody.enumerated() {
            guard let midiNote else { continue }
            notes.append(
                note(
                    midiNote,
                    beat: Double(step),
                    beats: step.isMultiple(of: 4) ? 0.72 : 0.46,
                    beatDuration: beat,
                    gain: 0.086,
                    pan: step.isMultiple(of: 2) ? -0.26 : 0.26,
                    instrument: .marimba
                )
            )
        }
        for beatOffset in [7.25, 15.25, 23.25, 31.0] {
            notes.append(
                note(
                    79,
                    beat: beatOffset,
                    beats: 0.30,
                    beatDuration: beat,
                    gain: 0.045,
                    pan: 0.42,
                    instrument: .naturePluck
                )
            )
        }

        var percussion: [ProceduralPercussionEvent] = []
        for beatIndex in stride(from: 0, to: 32, by: 4) {
            percussion.append(
                percussionEvent(
                    beat: Double(beatIndex),
                    beatDuration: beat,
                    gain: 0.110,
                    pan: -0.10,
                    voice: .softKick
                )
            )
            percussion.append(
                percussionEvent(
                    beat: Double(beatIndex) + 2.0,
                    beatDuration: beat,
                    gain: 0.050,
                    pan: 0.22,
                    voice: .woodblock
                )
            )
        }
        if emergency {
            percussion.append(
                contentsOf: emergencyBrushes(
                    totalBeats: 32,
                    interval: 1.0,
                    beatDuration: beat,
                    gain: 0.024
                )
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func firehouseRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // A bright 120 BPM parade march suggests teamwork and motion without
        // recreating a siren or using sharp alarm-like volume changes.
        let beat = 0.50
        let chords = [
            [57, 61, 64],
            [62, 66, 69],
            [54, 57, 61],
            [59, 62, 66],
            [52, 56, 59],
            [57, 61, 64],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 8,
            beat: beat,
            instrument: .warmPad,
            gain: 0.020
        )
        let roots = [45, 50, 42, 47, 40, 45]
        for (bar, root) in roots.enumerated() {
            for offset in [0.0, 2.0, 4.0, 6.0] {
                notes.append(
                    note(
                        root + (offset == 6 ? 7 : 0),
                        beat: Double(bar * 8) + offset,
                        beats: 0.50,
                        beatDuration: beat,
                        gain: offset == 0 ? 0.094 : 0.070,
                        pan: -0.08,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        let fanfarePatterns = [
            [69, 73, 76, 73, 69, 76, 78, 76],
            [74, 78, 81, 78, 74, 81, 83, 81],
            [66, 69, 73, 69, 66, 73, 74, 73],
            [71, 74, 78, 74, 71, 78, 81, 78],
            [64, 68, 71, 68, 64, 71, 73, 71],
            [69, 73, 76, 81, 78, 76, 73, 69],
        ]
        for (bar, pattern) in fanfarePatterns.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(bar * 8 + step),
                        beats: step == 6 ? 0.72 : 0.42,
                        beatDuration: beat,
                        gain: 0.082,
                        pan: step.isMultiple(of: 2) ? 0.24 : -0.24,
                        instrument: .mechanicalPluck
                    )
                )
            }
        }

        var percussion: [ProceduralPercussionEvent] = []
        for beatIndex in 0..<48 {
            if beatIndex.isMultiple(of: 2) {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.080,
                        pan: -0.10,
                        voice: .softKick
                    )
                )
            } else {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.055,
                        pan: 0.20,
                        voice: .woodblock
                    )
                )
            }
        }
        percussion.append(
            contentsOf: stride(from: 3.5, to: 48.0, by: 8.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.030,
                    pan: 0.38,
                    voice: .sparkle
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: emergencyBrushes(
                    totalBeats: 48,
                    interval: 0.5,
                    beatDuration: beat,
                    gain: 0.014
                )
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func brickworkRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // Six-beat building phrases click together like colorful blocks. Marimba
        // and wooden taps keep this city distinct from Build-It Bay's machinery.
        let beat = 0.50
        let chords = [
            [59, 62, 66],
            [64, 67, 71],
            [57, 60, 64],
            [62, 65, 69],
            [55, 59, 62],
            [60, 64, 67],
            [57, 60, 64],
            [59, 62, 66],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 6,
            beat: beat,
            instrument: .warmPad,
            gain: 0.018
        )
        let blockPatterns = [
            [71, 74, 78, 74, 78, 83],
            [76, 79, 83, 79, 83, 88],
            [69, 72, 76, 72, 76, 81],
            [74, 77, 81, 77, 81, 86],
            [67, 71, 74, 71, 74, 79],
            [72, 76, 79, 76, 79, 84],
            [69, 72, 76, 81, 76, 72],
            [71, 74, 78, 83, 78, 74],
        ]
        for (bar, pattern) in blockPatterns.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(bar * 6 + step),
                        beats: step == 5 ? 0.82 : 0.36,
                        beatDuration: beat,
                        gain: 0.080,
                        pan: Double(step - 2) * 0.10,
                        instrument: .marimba
                    )
                )
            }
        }
        let bassRoots = [47, 52, 45, 50, 43, 48, 45, 47]
        for (bar, root) in bassRoots.enumerated() {
            for offset in [0.0, 1.5, 3.0, 4.5] {
                notes.append(
                    note(
                        root + (offset == 4.5 ? 7 : 0),
                        beat: Double(bar * 6) + offset,
                        beats: 0.36,
                        beatDuration: beat,
                        gain: 0.070,
                        pan: -0.06,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        var percussion = stride(from: 0.5, to: 48.0, by: 1.0).map {
            percussionEvent(
                beat: $0,
                beatDuration: beat,
                gain: 0.044,
                pan: $0.truncatingRemainder(dividingBy: 2) < 1 ? -0.32 : 0.32,
                voice: .woodblock
            )
        }
        percussion.append(
            contentsOf: stride(from: 0.0, to: 48.0, by: 3.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.066,
                    pan: -0.10,
                    voice: .softKick
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: emergencyBrushes(
                    totalBeats: 48,
                    interval: 0.75,
                    beatDuration: beat,
                    gain: 0.016
                )
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func frostlightRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // A spacious 75 BPM waltz with twice-per-beat crystal motion feels icy
        // and magical while the low pad keeps the learning screen calm.
        let beat = 0.80
        let chords = [
            [52, 56, 59, 64],
            [57, 61, 64, 69],
            [49, 52, 56, 61],
            [54, 57, 61, 66],
            [52, 56, 59, 64],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 6,
            beat: beat,
            instrument: .warmPad,
            gain: 0.022
        )
        let crystalPatterns = [
            [76, 83, 80, 83, 88, 83, 80, 83, 76, 80, 83, 80],
            [81, 88, 85, 88, 93, 88, 85, 88, 81, 85, 88, 85],
            [73, 80, 76, 80, 85, 80, 76, 80, 73, 76, 80, 76],
            [78, 85, 81, 85, 90, 85, 81, 85, 78, 81, 85, 81],
            [76, 83, 80, 88, 83, 80, 76, 80, 83, 88, 92, 88],
        ]
        for (phrase, pattern) in crystalPatterns.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(phrase * 6) + Double(step) * 0.5,
                        beats: step == 11 ? 0.45 : 0.28,
                        beatDuration: beat,
                        gain: 0.064,
                        pan: step.isMultiple(of: 2) ? -0.36 : 0.36,
                        instrument: .glockenspiel
                    )
                )
            }
        }
        for (phrase, root) in [40, 45, 37, 42, 40].enumerated() {
            for offset in [0.0, 3.0] {
                notes.append(
                    note(
                        root,
                        beat: Double(phrase * 6) + offset,
                        beats: 1.10,
                        beatDuration: beat,
                        gain: 0.050,
                        pan: -0.05,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        var percussion = stride(from: 1.0, to: 30.0, by: 3.0).map {
            percussionEvent(
                beat: $0,
                beatDuration: beat,
                gain: 0.024,
                pan: 0.30,
                voice: .sparkle
            )
        }
        percussion.append(
            contentsOf: stride(from: 0.0, to: 30.0, by: 6.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.042,
                    pan: -0.10,
                    voice: .softKick
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: emergencyBrushes(
                    totalBeats: 30,
                    interval: 0.75,
                    beatDuration: beat,
                    gain: 0.012
                )
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func coasterRecipe(emergency: Bool) -> AmbientMusicRecipe {
        // The fastest score races through ten short rises and drops at 150 BPM.
        // A syncopated bass provides momentum without increasing the safe peak.
        let beat = 0.40
        let chords = [
            [58, 62, 65], [63, 67, 70], [55, 58, 62], [60, 63, 67], [53, 57, 60],
            [58, 62, 65], [65, 69, 72], [60, 63, 67], [55, 58, 62], [58, 62, 65],
        ]
        var notes = chordBed(
            chords: chords,
            beatsPerChord: 6,
            beat: beat,
            instrument: .warmPad,
            gain: 0.016
        )
        let ridePatterns = [
            [70, 74, 77, 82, 77, 74], [75, 79, 82, 87, 82, 79],
            [67, 70, 74, 79, 74, 70], [72, 75, 79, 84, 79, 75],
            [65, 69, 72, 77, 72, 69], [70, 74, 77, 82, 86, 82],
            [77, 81, 84, 89, 84, 81], [72, 75, 79, 84, 87, 84],
            [67, 70, 74, 79, 82, 79], [70, 74, 77, 82, 86, 89],
        ]
        for (phrase, pattern) in ridePatterns.enumerated() {
            for (step, midiNote) in pattern.enumerated() {
                notes.append(
                    note(
                        midiNote,
                        beat: Double(phrase * 6 + step),
                        beats: step == 5 ? 0.78 : 0.34,
                        beatDuration: beat,
                        gain: 0.078,
                        pan: Double(step - 2) * 0.11,
                        instrument: .mechanicalPluck
                    )
                )
            }
        }
        let roots = [46, 51, 43, 48, 41, 46, 53, 48, 43, 46]
        for (phrase, root) in roots.enumerated() {
            for offset in [0.0, 1.5, 3.0, 4.0, 5.0] {
                notes.append(
                    note(
                        root + (offset == 5 ? 12 : 0),
                        beat: Double(phrase * 6) + offset,
                        beats: 0.32,
                        beatDuration: beat,
                        gain: 0.072,
                        pan: -0.08,
                        instrument: .bouncyBass
                    )
                )
            }
        }

        var percussion: [ProceduralPercussionEvent] = []
        for beatIndex in 0..<60 {
            if beatIndex.isMultiple(of: 3) {
                percussion.append(
                    percussionEvent(
                        beat: Double(beatIndex),
                        beatDuration: beat,
                        gain: 0.066,
                        pan: -0.12,
                        voice: .softKick
                    )
                )
            }
            percussion.append(
                percussionEvent(
                    beat: Double(beatIndex) + 0.5,
                    beatDuration: beat,
                    gain: 0.027,
                    pan: beatIndex.isMultiple(of: 2) ? -0.34 : 0.34,
                    voice: .woodblock
                )
            )
        }
        percussion.append(
            contentsOf: stride(from: 5.5, to: 60.0, by: 6.0).map {
                percussionEvent(
                    beat: $0,
                    beatDuration: beat,
                    gain: 0.026,
                    pan: 0.42,
                    voice: .sparkle
                )
            }
        )
        if emergency {
            percussion.append(
                contentsOf: emergencyBrushes(
                    totalBeats: 60,
                    interval: 0.5,
                    beatDuration: beat,
                    gain: 0.012
                )
            )
        }
        return AmbientMusicRecipe(
            duration: loopDuration,
            notes: notes,
            percussion: percussion
        )
    }

    private static func emergencyBrushes(
        totalBeats: Double,
        interval: Double,
        beatDuration: Double,
        gain: Double
    ) -> [ProceduralPercussionEvent] {
        stride(from: interval / 2, to: totalBeats, by: interval).map {
            percussionEvent(
                beat: $0,
                beatDuration: beatDuration,
                gain: gain,
                pan: $0.truncatingRemainder(dividingBy: interval * 2) < interval
                    ? -0.36
                    : 0.36,
                voice: .brush
            )
        }
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
