import AVFoundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class SpeechVoiceDesignTests: XCTestCase {
    private let policy = VoiceSelectionPolicy.canonicalTeacherAmericanEnglish

    func testTeacherAudioFallbackPreservesReadAndWriteLearningRoles() {
        XCTAssertEqual(
            TeacherAudioFallbackPolicy.spokenRole(for: .readHint),
            .learning
        )
        XCTAssertEqual(
            TeacherAudioFallbackPolicy.spokenRole(for: .writePrompt),
            .writeLearning
        )
    }

    func testPrefersPremiumNaturalTeacherVoiceBeforeCompactCharacterVoice() {
        let compactCharacter = candidate(
            id: "com.apple.eloquence.en-US.Sandy",
            name: "Sandy",
            gender: .unspecified,
            quality: .standard
        )
        let premiumTeacher = candidate(
            id: "com.apple.voice.premium.en-US.Ava",
            name: "Ava",
            gender: .female,
            quality: .premium
        )

        XCTAssertEqual(
            policy.select(from: [compactCharacter, premiumTeacher]),
            premiumTeacher
        )
    }

    func testPrefersHighestQualityCanonicalFemaleVoiceRegardlessOfInputOrder() {
        let standardFemale = candidate(
            id: "samantha-standard",
            name: "Samantha",
            gender: .female,
            quality: .standard
        )
        let enhancedFemale = candidate(
            id: "zoe-enhanced",
            name: "Zoe",
            gender: .female,
            quality: .enhanced
        )
        let premiumFemale = candidate(
            id: "ava-premium",
            name: "Ava",
            gender: .female,
            quality: .premium
        )

        XCTAssertEqual(
            policy.select(from: [standardFemale, premiumFemale, enhancedFemale]),
            premiumFemale
        )
        XCTAssertEqual(policy.select(from: [enhancedFemale, premiumFemale]), premiumFemale)
    }

    func testPrefersFemaleStandardOverMalePremiumInTargetLanguage() {
        let female = candidate(
            id: "female-standard",
            name: "Samantha",
            gender: .female,
            quality: .standard
        )
        let male = candidate(
            id: "male-premium",
            name: "Alex",
            gender: .male,
            quality: .premium
        )

        XCTAssertEqual(policy.select(from: [male, female]), female)
    }

    func testKnownFemaleNameHandlesUnspecifiedSystemGender() {
        let inferredFemale = candidate(
            id: "ava-enhanced",
            name: "Ava",
            gender: .unspecified,
            quality: .enhanced
        )
        let unspecified = candidate(
            id: "generic-premium",
            name: "Generic",
            gender: .unspecified,
            quality: .premium
        )

        XCTAssertEqual(policy.select(from: [unspecified, inferredFemale]), inferredFemale)
    }

    func testStableIdentifierAndNamePreferencesBreakOtherwiseEqualTies() {
        let tieBreakPolicy = VoiceSelectionPolicy(
            targetLanguage: "en-US",
            preferredIdentifiers: ["stable-choice"],
            preferredNames: ["Preferred Name"]
        )
        let identifierChoice = candidate(
            id: "stable-choice",
            name: "Other Name",
            gender: .female,
            quality: .enhanced
        )
        let nameChoice = candidate(
            id: "name-choice",
            name: "Preferred Name",
            gender: .female,
            quality: .enhanced
        )
        let other = candidate(
            id: "other-choice",
            name: "Other Name",
            gender: .female,
            quality: .enhanced
        )

        XCTAssertEqual(
            tieBreakPolicy.select(from: [nameChoice, other, identifierChoice]),
            identifierChoice
        )
        XCTAssertEqual(tieBreakPolicy.select(from: [other, nameChoice]), nameChoice)
    }

    func testCompactFallbackUsesClearSamanthaInsteadOfEloquencePersona() {
        let samantha = candidate(
            id: "com.apple.voice.compact.en-US.Samantha",
            name: "Samantha",
            gender: .female,
            quality: .standard
        )
        let sandy = candidate(
            id: "com.apple.eloquence.en-US.Sandy",
            name: "Sandy",
            gender: .unspecified,
            quality: .standard
        )

        XCTAssertEqual(policy.select(from: [sandy, samantha]), samantha)
    }

    func testIdentifierProvidesDeterministicFinalTieBreak() {
        let first = candidate(
            id: "a-stable",
            name: "Natural",
            gender: .female,
            quality: .standard
        )
        let second = candidate(
            id: "z-stable",
            name: "Natural",
            gender: .female,
            quality: .standard
        )

        XCTAssertEqual(policy.select(from: [second, first]), first)
        XCTAssertEqual(policy.select(from: [first, second]), first)
    }

    func testFallsBackFromAmericanFemaleToNaturalAmericanThenEnglishFemale() {
        let naturalAmerican = candidate(
            id: "natural-en-us",
            name: "Natural",
            gender: .unspecified,
            quality: .standard
        )
        let britishFemale = candidate(
            id: "female-en-gb",
            name: "Serena",
            language: "en-GB",
            gender: .female,
            quality: .premium
        )

        XCTAssertEqual(
            policy.select(from: [britishFemale, naturalAmerican]),
            naturalAmerican
        )
        XCTAssertEqual(policy.select(from: [britishFemale]), britishFemale)
        XCTAssertNil(policy.select(from: []))
    }

    func testAvoidsNoveltyVoiceWhenNaturalAmericanVoiceExists() {
        let novelty = candidate(
            id: "novelty-premium",
            name: "Jester",
            gender: .unspecified,
            quality: .premium
        )
        let natural = candidate(
            id: "natural-standard",
            name: "Natural",
            gender: .unspecified,
            quality: .standard
        )

        XCTAssertEqual(policy.select(from: [novelty, natural]), natural)
    }

    func testLearningDeliveryPreservesTargetAndContextExactly() {
        let word = "write"
        let context = "Please write your name."

        XCTAssertEqual(
            SpeechUtteranceDesignPolicy.design(text: word, role: .learning).text,
            word
        )
        XCTAssertEqual(
            SpeechUtteranceDesignPolicy.design(text: context, role: .learning).text,
            context
        )
    }

    func testBrandDeliveryIsBrighterWhileLearningDeliveryStaysClear() {
        let brand = SpeechUtteranceDesignPolicy.design(
            text: "Tada Words!",
            role: .brand
        )
        let learning = SpeechUtteranceDesignPolicy.design(
            text: "apple",
            role: .learning
        )

        XCTAssertGreaterThan(brand.rate, learning.rate)
        XCTAssertGreaterThan(brand.pitchMultiplier, learning.pitchMultiplier)
        XCTAssertLessThan(brand.volume, learning.volume)
        XCTAssertEqual(
            learning.rate,
            AVSpeechUtteranceDefaultSpeechRate / 1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(learning.pitchMultiplier, 1.0, accuracy: 0.001)
    }

    func testWriteDeliveryUsesClearCadenceAndProtectsTheWordEnding() {
        let read = SpeechUtteranceDesignPolicy.design(
            text: "at",
            role: .learning
        )
        let write = SpeechUtteranceDesignPolicy.design(
            text: "at",
            role: .writeLearning
        )

        XCTAssertEqual(write.text, "at")
        XCTAssertEqual(write.rate, read.rate, accuracy: 0.001)
        XCTAssertGreaterThan(write.volume, read.volume)
        XCTAssertGreaterThan(write.postUtteranceDelay, read.postUtteranceDelay)
        XCTAssertGreaterThanOrEqual(write.postUtteranceDelay, 0.35)
    }

    func testAppleIsolatedWordRateIsOnePointFiveTimesSlowerThanDefault() {
        let read = SpeechUtteranceDesignPolicy.design(text: "at", role: .learning)
        let write = SpeechUtteranceDesignPolicy.design(
            text: "at",
            role: .writeLearning
        )

        XCTAssertEqual(
            SpeechUtteranceDesignPolicy.appleIsolatedWordRate,
            AVSpeechUtteranceDefaultSpeechRate / 1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            read.rate,
            SpeechUtteranceDesignPolicy.appleIsolatedWordRate,
            accuracy: 0.001
        )
        XCTAssertEqual(
            write.rate,
            SpeechUtteranceDesignPolicy.appleIsolatedWordRate,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(read.postUtteranceDelay, 0.30)
        XCTAssertGreaterThanOrEqual(write.postUtteranceDelay, 0.38)
    }

    func testSlowerIsolatedWordRateDoesNotChangeOtherSpeechRoles() {
        let brand = SpeechUtteranceDesignPolicy.design(
            text: "Tada Words!",
            role: .brand
        )
        let enrollment = SpeechUtteranceDesignPolicy.design(
            text: "I see a happy dog.",
            role: .voiceEnrollment
        )

        XCTAssertEqual(brand.rate, 0.54, accuracy: 0.001)
        XCTAssertEqual(enrollment.rate, 0.37, accuracy: 0.001)
        XCTAssertEqual(LaunchVoiceDesignPolicy.utterance.rate, 0.42, accuracy: 0.001)
    }

    func testRegressionWordsUseReviewedPronunciationPlan() {
        let expectedIPA: [String: String?] = [
            "of": nil,
            "at": nil,
            "cat": nil,
            "come": nil,
            "look": "lʊk",
        ]

        for (word, ipa) in expectedIPA {
            let design = SpeechUtteranceDesignPolicy.design(
                text: word,
                role: .writeLearning
            )

            XCTAssertEqual(design.text, word)
            XCTAssertEqual(design.ipaPronunciation, ipa)
            XCTAssertTrue(design.addsSentenceBoundary)
        }
    }

    func testContextSentenceIsNeverRewrittenAsAnIsolatedPronunciation() {
        let design = SpeechUtteranceDesignPolicy.design(
            text: "Please look at the cat.",
            role: .writeLearning
        )

        XCTAssertEqual(design.text, "Please look at the cat.")
        XCTAssertNil(design.ipaPronunciation)
        XCTAssertFalse(design.addsSentenceBoundary)
    }

    func testUtteranceFactoryCarriesIPAAndSilentTerminalBoundary() {
        let design = SpeechUtteranceDesignPolicy.design(
            text: "look",
            role: .writeLearning
        )
        let utterance = SpeechUtteranceFactory.make(design: design)
        let ipaKey = NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute)

        XCTAssertEqual(utterance.speechString, "look.")
        XCTAssertEqual(
            utterance.attributedSpeechString.attribute(
                ipaKey,
                at: 0,
                effectiveRange: nil
            ) as? String,
            "lʊk"
        )
        XCTAssertNil(
            utterance.attributedSpeechString.attribute(
                ipaKey,
                at: 4,
                effectiveRange: nil
            )
        )
    }

    func testOfUsesClearSystemLexiconWithoutHarmfulIPAOverride() {
        let design = SpeechUtteranceDesignPolicy.design(
            text: "of",
            role: .writeLearning
        )
        let utterance = SpeechUtteranceFactory.make(design: design)

        XCTAssertNil(design.ipaPronunciation)
        XCTAssertTrue(design.addsSentenceBoundary)
        XCTAssertEqual(utterance.speechString, "of.")
    }

    func testOrdinaryIsolatedWordGetsBoundaryWithoutInventedIPA() {
        let design = SpeechUtteranceDesignPolicy.design(
            text: "dog",
            role: .writeLearning
        )
        let utterance = SpeechUtteranceFactory.make(design: design)

        XCTAssertNil(design.ipaPronunciation)
        XCTAssertTrue(design.addsSentenceBoundary)
        XCTAssertEqual(utterance.speechString, "dog.")
    }

    func testRegressionWordsEachRemainOneUnsplitUtterance() {
        for word in ["of", "at", "cat", "come", "look"] {
            let design = SpeechUtteranceDesignPolicy.design(
                text: word,
                role: .writeLearning
            )
            let utterance = SpeechUtteranceFactory.make(design: design)

            XCTAssertEqual(utterance.speechString, word + ".")
            XCTAssertFalse(utterance.speechString.contains(" "))
        }
    }

    func testCanonicalSystemFallbackIsDeterministic() {
        let female = candidate(
            id: "female",
            name: "Samantha",
            gender: .female,
            quality: .standard
        )
        let male = candidate(
            id: "male",
            name: "Alex",
            gender: .male,
            quality: .standard
        )

        let selected = policy.select(from: [male, female])

        XCTAssertEqual(selected, female)
    }

    func testVoiceEnrollmentKeepsItsLocalCadence() {
        let enrollment = SpeechUtteranceDesignPolicy.design(
            text: "I see a happy dog.",
            role: .voiceEnrollment
        )

        XCTAssertEqual(enrollment.rate, 0.37, accuracy: 0.001)
        XCTAssertEqual(enrollment.text, "I see a happy dog.")
    }

    func testLaunchVoiceKeepsNaturalBrandPhraseInOneUtterance() {
        let utterance = LaunchVoiceDesignPolicy.utterance

        XCTAssertEqual(utterance.text, "Tah-DAH, words!")
        XCTAssertEqual(utterance.pitchMultiplier, 1.10, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(utterance.rate, 0.40)
        XCTAssertLessThanOrEqual(utterance.rate, 0.46)
        XCTAssertGreaterThanOrEqual(utterance.postUtteranceDelay, 0.20)
    }

    func testLaunchVoiceSSMLCarriesStressPauseAndFallingLanding() throws {
        let ssml = LaunchVoiceDesignPolicy.ssmlRepresentation

        XCTAssertTrue(ssml.contains(">tah-DAH</prosody>"))
        XCTAssertFalse(ssml.contains("tah-<emphasis"))
        XCTAssertTrue(ssml.contains("<break time=\"105ms\"/>"))
        XCTAssertTrue(ssml.contains("pitch=\"+7%\""))
        XCTAssertTrue(ssml.contains("pitch=\"-10%\""))

        let parsed = try XCTUnwrap(AVSpeechUtterance(ssmlRepresentation: ssml))
        XCTAssertEqual(parsed.speechString, "tah-DAH words!")
        XCTAssertFalse(parsed.speechString.contains("tah- DAH"))
    }

    private func candidate(
        id: String,
        name: String,
        language: String = "en-US",
        gender: SpeechVoiceCandidate.Gender,
        quality: SpeechVoiceCandidate.Quality
    ) -> SpeechVoiceCandidate {
        SpeechVoiceCandidate(
            identifier: id,
            name: name,
            language: language,
            gender: gender,
            quality: quality
        )
    }
}
