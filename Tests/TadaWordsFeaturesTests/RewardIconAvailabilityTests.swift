#if canImport(AppKit)
    import AppKit
    import TadaWordsContent
    import TadaWordsDomain
    import XCTest

    final class RewardIconAvailabilityTests: XCTestCase {
        func testEveryCatalogTreasureUsesAnAvailableSystemSymbol() {
            let catalog = ThemedRewardCatalog()

            for world in WorldTheme.allCases {
                for item in catalog.items(for: world) {
                    XCTAssertNotNil(
                        NSImage(
                            systemSymbolName: item.iconAssetID,
                            accessibilityDescription: item.displayName
                        ),
                        "Missing treasure icon \(item.iconAssetID) for \(item.id)"
                    )
                }
            }
        }
    }
#endif
