import Foundation
import TadaWordsDomain
import XCTest

final class WorldThemeCatalogTests: XCTestCase {
    func testStableWorldOrderAppendsNewThemesAfterOriginalThree() {
        XCTAssertEqual(
            WorldTheme.allCases,
            [
                .moonpetalKingdom,
                .buildItBay,
                .pawsAndPines,
                .dinoDiscovery,
                .firehouseHeroes,
                .brickworkCity,
                .frostlightWorld,
                .coasterCarnival,
            ]
        )
        XCTAssertEqual(CosmeticProgressionCatalog.worlds, WorldTheme.allCases)
    }

    func testEveryWorldHasDistinctChildFacingIdentity() {
        XCTAssertEqual(Set(WorldTheme.allCases.map(\.displayName)).count, 8)
        XCTAssertEqual(Set(WorldTheme.allCases.map(\.category)).count, 8)
    }

    func testWorldRawValuesRoundTripThroughCodable() throws {
        for world in WorldTheme.allCases {
            let encoded = try JSONEncoder().encode(world)
            let decoded = try JSONDecoder().decode(WorldTheme.self, from: encoded)
            XCTAssertEqual(decoded, world)
        }
    }
}
