import TadaWordsDesignSystem
import XCTest

@testable import TadaWordsFeatures

final class ReadWordColorPolicyTests: XCTestCase {
    func testEveryWorldHasOneRelevantUniqueFixedToken() {
        let tokens = TadaWorldID.allCases.map {
            TadaReadWordColorPalette.token(for: $0)
        }

        XCTAssertEqual(Set(tokens.map(\.id)).count, TadaWorldID.allCases.count)
        XCTAssertEqual(
            Set(tokens.map { "\($0.red)|\($0.green)|\($0.blue)" }).count,
            TadaWorldID.allCases.count
        )
        for world in TadaWorldID.allCases {
            XCTAssertTrue(
                TadaReadWordColorPalette.token(for: world).id.hasPrefix(
                    worldIDPrefix(for: world)
                ),
                world.rawValue
            )
        }
    }

    func testEveryWorldTokenMeetsWCAGContrastAgainstTheRenderedCardSurface() {
        let cardSurface = TadaReadWordColorPalette.cardSurface

        for world in TadaWorldID.allCases {
            let token = TadaReadWordColorPalette.token(for: world)
            XCTAssertGreaterThanOrEqual(
                token.contrastRatio(against: cardSurface),
                4.5,
                "\(token.id) must remain readable on the Read card"
            )
        }
    }

    func testEveryReadWordInAWorldUsesTheSameDesignToken() {
        for world in TadaWorldID.allCases {
            let expected = TadaReadWordColorPalette.token(for: world)
            let selected = Set(
                (1...64).map { _ in
                    ReadWordColorPolicy.token(worldID: world)
                })

            XCTAssertEqual(selected, [expected], world.rawValue)
        }
    }

    func testChangingWorldChangesTheReadWordToken() {
        let selected = TadaWorldID.allCases.map { world in
            ReadWordColorPolicy.token(worldID: world)
        }

        XCTAssertEqual(Set(selected.map(\.id)).count, TadaWorldID.allCases.count)
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
