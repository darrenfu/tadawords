import Foundation
import TadaWordsDomain

public protocol RewardCatalogProviding: Sendable {
    func items(for world: WorldTheme) -> [RewardCatalogItem]
    func reward(for key: RewardGrantKey) -> RewardCatalogItem
}

/// A small, original MVP catalog with stable item identifiers. Selection is a
/// calendar rotation, not Swift's randomized `Hashable` implementation, so the
/// same grant key always resolves to the same reward after an app restart.
public struct ThemedRewardCatalog: RewardCatalogProviding {
    private let itemsByWorld: [WorldTheme: [RewardCatalogItem]]

    public init() {
        itemsByWorld = [
            .moonpetalKingdom: Self.smallItems(
                world: .moonpetalKingdom,
                values: [
                    ("starlight-tiara", "Starlight Tiara"),
                    ("cloud-carriage", "Cloud Carriage"),
                    ("moon-ribbon", "Moon Ribbon"),
                    ("crystal-slippers", "Crystal Slippers"),
                    ("royal-lantern", "Royal Lantern"),
                    ("pearl-castle", "Pearl Castle"),
                    ("rose-scepter", "Rose Scepter"),
                    ("comet-cape", "Comet Cape"),
                    ("sunbeam-fan", "Sunbeam Fan"),
                    ("lily-crown", "Lily Crown"),
                    ("silver-harp", "Silver Harp"),
                    ("wish-journal", "Wish Journal"),
                    ("opal-mirror", "Opal Mirror"),
                    ("dove-brooch", "Dove Brooch"),
                    ("aurora-gloves", "Aurora Gloves"),
                    ("garden-key", "Garden Key"),
                    ("star-cookie", "Star Cookie"),
                    ("velvet-banner", "Velvet Banner"),
                    ("rainbow-goblet", "Rainbow Goblet"),
                    ("moonstone-ring", "Moonstone Ring"),
                ]
            )
                + Self.milestones(
                    world: .moonpetalKingdom,
                    values: [
                        ("royal-garden", "Royal Garden", 3),
                        ("moonlit-ballroom", "Moonlit Ballroom", 8),
                        ("sky-palace", "Sky Palace", 15),
                        ("friendship-parade", "Friendship Parade", 25),
                        ("kingdom-constellation", "Kingdom Constellation", 40),
                    ]
                ),
            .buildItBay: Self.smallItems(
                world: .buildItBay,
                values: [
                    ("golden-excavator", "Golden Excavator"),
                    ("tower-crane", "Tower Crane"),
                    ("mighty-bulldozer", "Mighty Bulldozer"),
                    ("cement-spinner", "Cement Spinner"),
                    ("road-roller", "Road Roller"),
                    ("builder-badge", "Builder Badge"),
                    ("rescue-loader", "Rescue Loader"),
                    ("mini-backhoe", "Mini Backhoe"),
                    ("bridge-beam", "Bridge Beam"),
                    ("safety-helmet", "Safety Helmet"),
                    ("traffic-cones", "Traffic Cones"),
                    ("dump-truck", "Dump Truck"),
                    ("tool-chest", "Tool Chest"),
                    ("blueprint-roll", "Blueprint Roll"),
                    ("work-lights", "Work Lights"),
                    ("forklift", "Forklift"),
                    ("grader", "Road Grader"),
                    ("tunnel-drill", "Tunnel Drill"),
                    ("site-radio", "Site Radio"),
                    ("steel-girder", "Steel Girder"),
                ]
            )
                + Self.milestones(
                    world: .buildItBay,
                    values: [
                        ("harbor-road", "Harbor Road", 3),
                        ("rainbow-bridge", "Rainbow Bridge", 8),
                        ("working-lighthouse", "Working Lighthouse", 15),
                        ("builder-town", "Builder Town", 25),
                        ("great-bay-project", "Great Bay Project", 40),
                    ]
                ),
            .pawsAndPines: Self.smallItems(
                world: .pawsAndPines,
                values: [
                    ("fox-scout", "Fox Scout"),
                    ("panda-picnic", "Panda Picnic"),
                    ("otter-slide", "Otter Slide"),
                    ("bunny-burrow", "Bunny Burrow"),
                    ("owl-lantern", "Owl Lantern"),
                    ("bear-cabin", "Bear Cabin"),
                    ("deer-compass", "Deer Compass"),
                    ("squirrel-acorn", "Squirrel Acorn"),
                    ("hedgehog-hat", "Hedgehog Hat"),
                    ("raccoon-pack", "Raccoon Pack"),
                    ("beaver-paddle", "Beaver Paddle"),
                    ("moose-mug", "Moose Mug"),
                    ("robin-scarf", "Robin Scarf"),
                    ("frog-boots", "Frog Boots"),
                    ("badger-map", "Badger Map"),
                    ("duckling-kite", "Duckling Kite"),
                    ("wolf-whistle", "Wolf Whistle"),
                    ("chipmunk-basket", "Chipmunk Basket"),
                    ("lynx-binoculars", "Lynx Binoculars"),
                    ("mushroom-lamp", "Mushroom Lamp"),
                ]
            )
                + Self.milestones(
                    world: .pawsAndPines,
                    values: [
                        ("creek-crossing", "Creek Crossing", 3),
                        ("treetop-clubhouse", "Treetop Clubhouse", 8),
                        ("forest-festival", "Forest Festival", 15),
                        ("wildlife-sanctuary", "Wildlife Sanctuary", 25),
                        ("great-northern-lights", "Great Northern Lights", 40),
                    ]
                ),
        ]
    }

    public func items(for world: WorldTheme) -> [RewardCatalogItem] {
        itemsByWorld[world] ?? []
    }

    public func reward(for key: RewardGrantKey) -> RewardCatalogItem {
        let candidates = items(for: key.world).filter {
            $0.tier == .smallCollectible
        }
        precondition(!candidates.isEmpty, "Every world must have reward items")
        return candidates[rotationIndex(for: key, count: candidates.count)]
    }

    private func rotationIndex(for key: RewardGrantKey, count: Int) -> Int {
        let profileOffset = key.profileID.rawValue.uuidString.utf8.reduce(0) {
            ($0 + Int($1)) % count
        }
        let modeOffset = key.learningMode == .read ? 0 : 1
        let dayOffset = dayOrdinal(key.localDay) % count
        return (profileOffset + modeOffset + dayOffset) % count
    }

    private func dayOrdinal(_ localDay: LocalDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(
            from: DateComponents(year: 1970, month: 1, day: 1)
        )!
        let date = calendar.date(
            from: DateComponents(
                year: localDay.year,
                month: localDay.month,
                day: localDay.day
            )
        )!
        return calendar.dateComponents([.day], from: reference, to: date).day!
    }

    private static func smallItems(
        world: WorldTheme,
        values: [(String, String)]
    ) -> [RewardCatalogItem] {
        values.map { slug, displayName in
            RewardCatalogItem(
                id: RewardItemID(rawValue: "\(world.rawValue).\(slug)"),
                world: world,
                displayName: displayName
            )
        }
    }

    private static func milestones(
        world: WorldTheme,
        values: [(String, String, Int)]
    ) -> [RewardCatalogItem] {
        values.map { slug, displayName, requiredCount in
            RewardCatalogItem(
                id: RewardItemID(rawValue: "\(world.rawValue).milestone.\(slug)"),
                world: world,
                displayName: displayName,
                tier: .milestone,
                requiredTodayQuestCount: requiredCount
            )
        }
    }
}
