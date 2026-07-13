import Foundation
import TadaWordsDesignSystem
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class ReadWordColorPolicyTests: XCTestCase {
    func testEveryWorldHasARelevantVariedPalette() {
        for world in TadaWorldID.allCases {
            let tokens = TadaReadWordColorPalette.tokens(for: world)

            XCTAssertGreaterThanOrEqual(tokens.count, 3, world.rawValue)
            XCTAssertEqual(Set(tokens.map(\.id)).count, tokens.count, world.rawValue)
            XCTAssertTrue(
                tokens.allSatisfy { $0.id.hasPrefix(worldIDPrefix(for: world)) },
                world.rawValue
            )
        }
    }

    func testEveryWordColorMeetsWCAGContrastAgainstTheRenderedCardSurface() {
        let cardSurface = TadaReadWordColorPalette.cardSurface

        for world in TadaWorldID.allCases {
            for token in TadaReadWordColorPalette.tokens(for: world) {
                XCTAssertGreaterThanOrEqual(
                    token.contrastRatio(against: cardSurface),
                    4.5,
                    "\(token.id) must remain readable on the Read card"
                )
            }
        }
    }

    func testSameQuestWordAndItemAlwaysReturnsTheSameToken() {
        let identity = identity(number: 1)
        let first = ReadWordColorPolicy.token(
            worldID: .moonpetal,
            questID: identity.questID,
            promptID: identity.promptID,
            currentItem: identity.currentItem
        )

        for _ in 0..<20 {
            XCTAssertEqual(
                ReadWordColorPolicy.token(
                    worldID: .moonpetal,
                    questID: identity.questID,
                    promptID: identity.promptID,
                    currentItem: identity.currentItem
                ),
                first
            )
        }
    }

    func testManyQuestAndWordIdentitiesUseAtLeastThreeColorsInEveryWorld() {
        for world in TadaWorldID.allCases {
            let selected = Set(
                (1...64).map { number in
                    let value = identity(number: number)
                    return ReadWordColorPolicy.token(
                        worldID: world,
                        questID: value.questID,
                        promptID: value.promptID,
                        currentItem: value.currentItem
                    ).id
                })

            XCTAssertGreaterThanOrEqual(selected.count, 3, world.rawValue)
        }
    }

    func testQuestPromptAndItemEachParticipateInTheStableIdentity() {
        let world = TadaWorldID.frostlightWorld
        let fixedQuest = questID(number: 700)
        let fixedPrompt = promptID(number: 800)
        let questColors = Set(
            (1...32).map { number in
                ReadWordColorPolicy.token(
                    worldID: world,
                    questID: questID(number: number),
                    promptID: fixedPrompt,
                    currentItem: 1
                ).id
            })
        let promptColors = Set(
            (1...32).map { number in
                ReadWordColorPolicy.token(
                    worldID: world,
                    questID: fixedQuest,
                    promptID: promptID(number: number),
                    currentItem: 1
                ).id
            })
        let itemColors = Set(
            (1...16).map { item in
                ReadWordColorPolicy.token(
                    worldID: world,
                    questID: fixedQuest,
                    promptID: fixedPrompt,
                    currentItem: item
                ).id
            })

        XCTAssertGreaterThan(questColors.count, 1)
        XCTAssertGreaterThan(promptColors.count, 1)
        XCTAssertGreaterThan(itemColors.count, 1)
    }

    func testTheWorldParticipatesInSelectionWithoutEncodingAttemptOutcome() {
        let value = identity(number: 9)
        let selected = TadaWorldID.allCases.map { world in
            ReadWordColorPolicy.token(
                worldID: world,
                questID: value.questID,
                promptID: value.promptID,
                currentItem: value.currentItem
            )
        }

        XCTAssertEqual(Set(selected.map(\.id)).count, TadaWorldID.allCases.count)
    }

    private func identity(number: Int) -> (
        questID: QuestID,
        promptID: WordPromptID,
        currentItem: Int
    ) {
        let questSuffix = String(format: "%012X", number)
        let promptSuffix = String(format: "%012X", number + 10_000)
        return (
            QuestID(rawValue: stableUUID(prefix: "81", suffix: questSuffix)),
            WordPromptID(rawValue: stableUUID(prefix: "82", suffix: promptSuffix)),
            ((number - 1) % 8) + 1
        )
    }

    private func questID(number: Int) -> QuestID {
        QuestID(
            rawValue: stableUUID(
                prefix: "83",
                suffix: String(format: "%012X", number)
            )
        )
    }

    private func promptID(number: Int) -> WordPromptID {
        WordPromptID(
            rawValue: stableUUID(
                prefix: "84",
                suffix: String(format: "%012X", number)
            )
        )
    }

    private func stableUUID(prefix: String, suffix: String) -> UUID {
        UUID(uuidString: "\(prefix)000000-0000-0000-0000-\(suffix)")!
    }

    private func worldIDPrefix(for world: TadaWorldID) -> String {
        switch world {
        case .moonpetal:
            "moonpetal-"
        case .buildItBay:
            "buildit-"
        case .pawsAndPines:
            "paws-"
        case .dinoDiscovery:
            "dino-"
        case .firehouseHeroes:
            "firehouse-"
        case .brickworkCity:
            "brickwork-"
        case .frostlightWorld:
            "frostlight-"
        case .coasterCarnival:
            "coaster-"
        }
    }
}
