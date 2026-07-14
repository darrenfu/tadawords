import AVFoundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class ProceduralAudioTests: XCTestCase {
    func testAmbientCacheInvokesRendererOnlyOnceForRepeatedRecordingRecovery() {
        var cache = AmbientBufferCache<Int>()
        let key = AmbientScoreKey(
            world: .moonpetalKingdom,
            isEmergency: false
        )
        var renderCount = 0

        let first = cache.value(for: key) {
            renderCount += 1
            return 42
        }
        let recovered = cache.value(for: key) {
            renderCount += 1
            return 99
        }

        XCTAssertEqual(first, 42)
        XCTAssertEqual(recovered, 42)
        XCTAssertEqual(renderCount, 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testAmbientCacheRetainsOnlyTheCurrentWorldsTwoVariants() {
        var cache = AmbientBufferCache<Int>()
        let moonNormal = AmbientScoreKey(
            world: .moonpetalKingdom,
            isEmergency: false
        )
        let moonEmergency = AmbientScoreKey(
            world: .moonpetalKingdom,
            isEmergency: true
        )
        let buildNormal = AmbientScoreKey(
            world: .buildItBay,
            isEmergency: false
        )

        XCTAssertEqual(cache.value(for: moonNormal) { 1 }, 1)
        XCTAssertEqual(cache.value(for: moonEmergency) { 2 }, 2)
        XCTAssertEqual(cache.count, 2)

        XCTAssertEqual(cache.value(for: buildNormal) { 3 }, 3)

        XCTAssertTrue(cache.contains(buildNormal))
        XCTAssertFalse(cache.contains(moonNormal))
        XCTAssertFalse(cache.contains(moonEmergency))
        XCTAssertEqual(cache.count, 1)
    }

    func testAmbientCacheNeverReusesNormalBufferForEmergencyMix() {
        var cache = AmbientBufferCache<Int>()
        let normal = AmbientScoreKey(
            world: .pawsAndPines,
            isEmergency: false
        )
        let emergency = AmbientScoreKey(
            world: .pawsAndPines,
            isEmergency: true
        )
        var normalRenderCount = 0
        var emergencyRenderCount = 0

        XCTAssertEqual(
            cache.value(for: normal) {
                normalRenderCount += 1
                return 10
            },
            10
        )
        XCTAssertEqual(
            cache.value(for: emergency) {
                emergencyRenderCount += 1
                return 20
            },
            20
        )
        XCTAssertEqual(cache.value(for: normal) { 99 }, 10)
        XCTAssertEqual(cache.value(for: emergency) { 99 }, 20)
        XCTAssertEqual(normalRenderCount, 1)
        XCTAssertEqual(emergencyRenderCount, 1)
        XCTAssertEqual(cache.count, 2)
    }

    func testSelectingNewWorldImmediatelyReleasesCachedVariants() {
        var cache = AmbientBufferCache<Int>()
        let normal = AmbientScoreKey(
            world: .moonpetalKingdom,
            isEmergency: false
        )
        let emergency = AmbientScoreKey(
            world: .moonpetalKingdom,
            isEmergency: true
        )
        _ = cache.value(for: normal) { 1 }
        _ = cache.value(for: emergency) { 2 }

        cache.select(world: .buildItBay)

        XCTAssertEqual(cache.count, 0)
        XCTAssertFalse(cache.contains(normal))
        XCTAssertFalse(cache.contains(emergency))
    }

    func testFailedAmbientRenderDoesNotEvictOrPolluteCache() {
        enum RenderError: Error { case failed }

        var cache = AmbientBufferCache<Int>()
        let healthy = AmbientScoreKey(
            world: .pawsAndPines,
            isEmergency: false
        )
        let failing = AmbientScoreKey(
            world: .buildItBay,
            isEmergency: true
        )
        _ = cache.value(for: healthy) { 7 }

        XCTAssertThrowsError(
            try cache.value(for: failing) {
                throw RenderError.failed
            }
        )
        XCTAssertTrue(cache.contains(healthy))
        XCTAssertFalse(cache.contains(failing))
        XCTAssertEqual(cache.count, 1)
    }

    func testWorldPalettesAreMusicallyDistinct() {
        let worlds = WorldTheme.allCases
        let palettes = worlds.map(WorldAudioPalette.palette)

        XCTAssertEqual(worlds.count, 8)
        XCTAssertEqual(Set(palettes).count, worlds.count)

        let recipes = worlds.map {
            ProceduralMusicComposer.recipe(for: $0, emergency: false)
        }
        XCTAssertEqual(Set(recipes).count, worlds.count)
        XCTAssertTrue(recipes.allSatisfy { !$0.notes.isEmpty && !$0.percussion.isEmpty })
    }

    func testMoonpetalScoreIsUpbeatLayeredAndStillVoiceSafe() {
        let normal = ProceduralMusicComposer.recipe(
            for: .moonpetalKingdom,
            emergency: false
        )
        let emergency = ProceduralMusicComposer.recipe(
            for: .moonpetalKingdom,
            emergency: true
        )

        XCTAssertEqual(WorldAudioPalette.palette(for: .moonpetalKingdom).pulseInterval, 0.60)
        XCTAssertEqual(normal.duration, ProceduralMusicComposer.loopDuration)
        XCTAssertGreaterThanOrEqual(Set(normal.notes.map(\.instrument)).count, 4)
        XCTAssertGreaterThanOrEqual(Set(normal.percussion.map(\.voice)).count, 3)
        XCTAssertGreaterThan(normal.notes.count, 100)
        XCTAssertGreaterThan(normal.percussion.count, 60)
        XCTAssertGreaterThan(emergency.percussion.count, normal.percussion.count)
        XCTAssertTrue(normal.notes.allSatisfy { $0.start + $0.duration <= normal.duration })
        XCTAssertTrue(normal.percussion.allSatisfy { $0.start < normal.duration })

        let rendered = ProceduralAudioFactory.ambientLoop(
            world: .moonpetalKingdom,
            sampleRate: 22_050
        )
        XCTAssertEqual(
            peakAmplitude(in: rendered),
            ProceduralAudioFactory.ambientTargetPeak,
            accuracy: 0.0001
        )
        XCTAssertLessThan(
            AmbientMixPolicy.duckedVolume,
            AmbientMixPolicy.normalVolume * 0.20
        )
    }

    func testMoonpetalCelebrationLayersStayIsolatedToPrincessWorld() {
        let moonpetal = ProceduralMusicComposer.recipe(
            for: .moonpetalKingdom,
            emergency: false
        )
        let otherWorlds = WorldTheme.allCases.filter { $0 != .moonpetalKingdom }.map {
            ProceduralMusicComposer.recipe(for: $0, emergency: false)
        }

        XCTAssertTrue(moonpetal.notes.contains { $0.instrument == .harp })
        XCTAssertTrue(moonpetal.notes.contains { $0.instrument == .glockenspiel })
        XCTAssertTrue(moonpetal.notes.contains { $0.instrument == .bouncyBass })
        XCTAssertTrue(
            otherWorlds.allSatisfy { recipe in
                recipe.notes.allSatisfy { $0.instrument != .harp }
            }
        )
        XCTAssertTrue(
            ProceduralMusicComposer.recipe(for: .frostlightWorld, emergency: false)
                .notes.contains { $0.instrument == .glockenspiel }
        )
    }

    func testEveryWorldScoreFitsTheLoopAndKeepsItsEmergencyLayer() {
        for world in WorldTheme.allCases {
            let normal = ProceduralMusicComposer.recipe(for: world, emergency: false)
            let emergency = ProceduralMusicComposer.recipe(for: world, emergency: true)

            XCTAssertEqual(normal.duration, ProceduralMusicComposer.loopDuration)
            XCTAssertTrue(normal.notes.allSatisfy { $0.start >= 0 })
            XCTAssertTrue(
                normal.notes.allSatisfy { $0.start + $0.duration <= normal.duration }
            )
            XCTAssertTrue(
                normal.percussion.allSatisfy { event in
                    event.start >= 0 && event.start < normal.duration
                }
            )
            XCTAssertEqual(normal.notes, emergency.notes)
            XCTAssertGreaterThan(emergency.percussion.count, normal.percussion.count)
        }
    }

    func testEveryFunctionalCueProducesAQuietFiniteBufferInEveryWorld() {
        let cues: [FunctionalAudioCue] = [
            .click,
            .correct,
            .validRetry,
            .technicalRetry,
            .star(index: 0),
            .star(index: 1),
            .star(index: 2),
            .reward,
            .writing(tool: .pencil),
            .writing(tool: .crayon),
            .writing(tool: .chalk),
            .writing(tool: .brush),
        ]

        for world in WorldTheme.allCases {
            for cue in cues {
                let buffer = ProceduralAudioFactory.effect(
                    cue: cue,
                    world: world,
                    sampleRate: 44_100
                )
                XCTAssertGreaterThan(buffer.frameLength, 0)
                XCTAssertLessThanOrEqual(peakAmplitude(in: buffer), 0.72)
                XCTAssertGreaterThan(peakAmplitude(in: buffer), 0)
            }
        }
    }

    func testWritingToolsProduceFourDistinctShortVoiceSafeTextures() {
        let buffers = HandwritingTool.allCases.map {
            ProceduralAudioFactory.writingEffect(
                tool: $0,
                sampleRate: 44_100
            )
        }

        XCTAssertEqual(Set(buffers.map(fingerprint)).count, HandwritingTool.allCases.count)
        for buffer in buffers {
            XCTAssertGreaterThan(buffer.frameLength, 0)
            XCTAssertLessThanOrEqual(buffer.frameLength, 3_087)
            XCTAssertGreaterThan(peakAmplitude(in: buffer), 0.01)
            XCTAssertLessThanOrEqual(
                peakAmplitude(in: buffer),
                ProceduralAudioFactory.writingTargetPeak
            )
            XCTAssertLessThan(loopBoundaryDiscontinuity(in: buffer), 0.002)
        }
    }

    func testWritingCueThrottleRejectsTouchBurstsWithoutBuildingAQueue() {
        var throttle = WritingCueThrottle()

        XCTAssertTrue(throttle.accepts(at: 10))
        XCTAssertFalse(throttle.accepts(at: 10.02))
        XCTAssertFalse(throttle.accepts(at: 10.10))
        XCTAssertTrue(throttle.accepts(at: 10.12))
        XCTAssertFalse(throttle.accepts(at: 10.15))

        throttle.reset()
        XCTAssertTrue(throttle.accepts(at: 10.15))
    }

    func testAmbientLoopsAreTwentyFourSecondStereoScoresWithDistinctContent() {
        let buffers = WorldTheme.allCases.map {
            ProceduralAudioFactory.ambientLoop(
                world: $0,
                sampleRate: 44_100
            )
        }

        XCTAssertTrue(buffers.allSatisfy { $0.frameLength == 1_058_400 })
        XCTAssertTrue(buffers.allSatisfy { $0.format.channelCount == 2 })
        let fingerprints = buffers.map(fingerprint)
        XCTAssertEqual(Set(fingerprints).count, WorldTheme.allCases.count)

        for buffer in buffers {
            XCTAssertEqual(
                peakAmplitude(in: buffer),
                ProceduralAudioFactory.ambientTargetPeak,
                accuracy: 0.0001
            )
            XCTAssertLessThan(loopBoundaryDiscontinuity(in: buffer), 0.001)
            XCTAssertTrue(quarterEnergies(in: buffer).allSatisfy { $0 > 0.002 })
        }
    }

    func testEmergencyRhythmChangesEveryScoreWithoutIncreasingItsPeak() {
        for world in WorldTheme.allCases {
            let normal = ProceduralAudioFactory.ambientLoop(
                world: world,
                sampleRate: 44_100
            )
            let emergency = ProceduralAudioFactory.ambientLoop(
                world: world,
                sampleRate: 44_100,
                emergency: true
            )

            XCTAssertNotEqual(fingerprint(normal), fingerprint(emergency))
            XCTAssertLessThanOrEqual(
                peakAmplitude(in: emergency),
                peakAmplitude(in: normal) + 0.0001
            )
        }
    }

    func testLaunchSignatureKeepsRoughlyOnePointTwoSecondEnergeticShape() {
        let buffer = ProceduralAudioFactory.launchSignature(
            world: .moonpetalKingdom,
            sampleRate: 44_100
        )

        XCTAssertEqual(buffer.frameLength, 52_920)
        XCTAssertGreaterThan(peakAmplitude(in: buffer), 0.20)
        XCTAssertLessThanOrEqual(peakAmplitude(in: buffer), 0.72)
    }

    func testCelebrationCuesStayBrighterThanGentleRetryCues() {
        for world in WorldTheme.allCases {
            let correct = ProceduralAudioFactory.effect(
                cue: .correct,
                world: world,
                sampleRate: 44_100
            )
            let reward = ProceduralAudioFactory.effect(
                cue: .reward,
                world: world,
                sampleRate: 44_100
            )
            let retry = ProceduralAudioFactory.effect(
                cue: .validRetry,
                world: world,
                sampleRate: 44_100
            )

            XCTAssertGreaterThan(peakAmplitude(in: correct), peakAmplitude(in: retry))
            XCTAssertGreaterThan(peakAmplitude(in: reward), peakAmplitude(in: retry))
            XCTAssertGreaterThan(correct.frameLength, retry.frameLength)
            XCTAssertGreaterThan(reward.frameLength, retry.frameLength)
        }
    }

    func testVoicePromptDuckingIsConservativeAndCrossfadeKeepsConstantGain() {
        XCTAssertLessThan(
            AmbientMixPolicy.duckedVolume,
            AmbientMixPolicy.normalVolume * 0.20
        )

        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            let gains = AmbientMixPolicy.crossfadeGains(progress: progress)
            XCTAssertEqual(gains.outgoing + gains.incoming, 1, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(gains.outgoing, 0)
            XCTAssertGreaterThanOrEqual(gains.incoming, 0)
        }
    }

    func testRepeatedActivationOfSamePlayingWorldDoesNotRestartScore() {
        XCTAssertEqual(
            AmbientMixPolicy.activationDecision(
                shouldPlay: true,
                scoreChanged: false,
                musicWasEnabled: true,
                activePlayerIsPlaying: true
            ),
            .updateVolume
        )
        XCTAssertEqual(
            AmbientMixPolicy.activationDecision(
                shouldPlay: true,
                scoreChanged: true,
                musicWasEnabled: true,
                activePlayerIsPlaying: true
            ),
            .transition(duration: AmbientMixPolicy.crossfadeDuration)
        )
        XCTAssertEqual(
            AmbientMixPolicy.activationDecision(
                shouldPlay: true,
                scoreChanged: false,
                musicWasEnabled: false,
                activePlayerIsPlaying: false
            ),
            .transition(duration: AmbientMixPolicy.fadeInDuration)
        )
        XCTAssertEqual(
            AmbientMixPolicy.activationDecision(
                shouldPlay: false,
                scoreChanged: false,
                musicWasEnabled: true,
                activePlayerIsPlaying: true
            ),
            .stop
        )
    }

    func testLateLaunchConfigurationPreservesAnActivatedChildScore() {
        XCTAssertEqual(
            AmbientMixPolicy.configurationDecision(
                ambientIsClaimedByChildSession: false
            ),
            .apply
        )
        XCTAssertEqual(
            AmbientMixPolicy.configurationDecision(
                ambientIsClaimedByChildSession: true
            ),
            .preserveActiveSession
        )
    }

    func testCancellingTransitionInvalidatesOlderAsyncFade() {
        var gate = AmbientTransitionGate()
        let first = gate.begin()
        XCTAssertTrue(gate.accepts(first))

        gate.cancel()
        XCTAssertFalse(gate.accepts(first))

        let second = gate.begin()
        XCTAssertTrue(gate.accepts(second))
        XCTAssertFalse(gate.accepts(first))
    }

    private func peakAmplitude(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        return (0..<Int(buffer.format.channelCount)).reduce(0) { peak, channelIndex in
            (0..<Int(buffer.frameLength)).reduce(peak) {
                max($0, abs(channels[channelIndex][$1]))
            }
        }
    }

    private func fingerprint(_ buffer: AVAudioPCMBuffer) -> Int {
        guard let channels = buffer.floatChannelData else { return 0 }
        return (0..<Int(buffer.format.channelCount)).reduce(0) { result, channelIndex in
            stride(from: 0, to: Int(buffer.frameLength), by: 997).reduce(result) {
                $0 &+ Int(channels[channelIndex][$1] * 100_000)
            }
        }
    }

    private func loopBoundaryDiscontinuity(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        for channelIndex in 0..<Int(buffer.format.channelCount) {
            peak = max(
                peak,
                abs(channels[channelIndex][0] - channels[channelIndex][frameCount - 1])
            )
        }
        return peak
    }

    private func quarterEnergies(in buffer: AVAudioPCMBuffer) -> [Double] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let quarterLength = frameCount / 4
        return (0..<4).map { quarter in
            let start = quarter * quarterLength
            let end = quarter == 3 ? frameCount : start + quarterLength
            var sum = 0.0
            var count = 0
            for channelIndex in 0..<Int(buffer.format.channelCount) {
                for frame in stride(from: start, to: end, by: 16) {
                    sum += Double(abs(channels[channelIndex][frame]))
                    count += 1
                }
            }
            return count == 0 ? 0 : sum / Double(count)
        }
    }
}
