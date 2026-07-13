import TadaWordsDesignSystem
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class WorldThemePresentationMappingTests: XCTestCase {
    func testEveryDomainWorldMapsToItsDistinctDesignTheme() {
        let mappedThemes = WorldTheme.allCases.map(TadaWorldTheme.from)

        XCTAssertEqual(
            mappedThemes.map(\.id),
            [
                .moonpetal,
                .buildItBay,
                .pawsAndPines,
                .dinoDiscovery,
                .firehouseHeroes,
                .brickworkCity,
                .frostlightWorld,
                .coasterCarnival,
            ]
        )
        XCTAssertEqual(Set(mappedThemes.map(\.name)).count, WorldTheme.allCases.count)
        XCTAssertEqual(
            Set(mappedThemes.map(\.rewardName)).count,
            WorldTheme.allCases.count
        )
    }

    func testDesignThemeCatalogMatchesDomainWorldCount() {
        XCTAssertEqual(TadaWorldTheme.all.count, WorldTheme.allCases.count)
        XCTAssertEqual(
            Set(TadaWorldTheme.all.map(\.id)),
            Set(TadaWorldID.allCases)
        )
    }
}
