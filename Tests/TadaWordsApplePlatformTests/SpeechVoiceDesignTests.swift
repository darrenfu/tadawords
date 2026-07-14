import AVFoundation
import XCTest

@testable import TadaWordsApplePlatform

final class SpeechVoiceDesignTests: XCTestCase {
    private let policy = VoiceSelectionPolicy.youthfulAmericanEnglish

    func testPrefersYouthfulNamedPersonaBeforeMaturePremiumFallback() {
        let youthful = candidate(
            id: "com.apple.eloquence.en-US.Sandy",
            name: "Sandy",
            gender: .unspecified,
            quality: .standard
        )
        let maturePremium = candidate(
            id: "com.apple.voice.premium.en-US.Ava",
            name: "Ava",
            gender: .female,
            quality: .premium
        )

        XCTAssertEqual(policy.select(from: [maturePremium, youthful]), youthful)
    }

    func testPrefersYouthfulFemalePersonaRegardlessOfInputOrder() {
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
            enhancedFemale
        )
        XCTAssertEqual(
            policy.select(from: [enhancedFemale, standardFemale, premiumFemale]),
            enhancedFemale
        )
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
        XCTAssertGreaterThan(brand.volume, learning.volume)
        XCTAssertGreaterThanOrEqual(learning.rate, 0.42)
        XCTAssertLessThanOrEqual(learning.rate, 0.48)
        XCTAssertGreaterThanOrEqual(learning.pitchMultiplier, 1.0)
        XCTAssertLessThanOrEqual(learning.pitchMultiplier, 1.10)
    }

    func testWriteDeliveryIsSlowerAndProtectsTheWordEnding() {
        let read = SpeechUtteranceDesignPolicy.design(
            text: "at",
            role: .learning
        )
        let write = SpeechUtteranceDesignPolicy.design(
            text: "at",
            role: .writeLearning
        )

        XCTAssertEqual(write.text, "at")
        XCTAssertLessThan(write.rate, read.rate)
        XCTAssertGreaterThan(write.postUtteranceDelay, read.postUtteranceDelay)
        XCTAssertGreaterThanOrEqual(write.postUtteranceDelay, 0.18)
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
