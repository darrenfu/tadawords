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
        let baseItems: [WorldTheme: [RewardCatalogItem]] = [
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
            .dinoDiscovery: Self.smallItems(
                world: .dinoDiscovery,
                values: [
                    ("tiny-t-rex", "Tiny T-Rex"),
                    ("triceratops-badge", "Triceratops Badge"),
                    ("fossil-shell", "Fossil Shell"),
                    ("raptor-footprint", "Raptor Footprint"),
                    ("dino-egg", "Dino Egg"),
                    ("stegosaurus-plate", "Stegosaurus Plate"),
                    ("amber-gem", "Amber Gem"),
                    ("jungle-compass", "Jungle Compass"),
                    ("explorer-hat", "Explorer Hat"),
                    ("bone-brush", "Bone Brush"),
                    ("volcano-rock", "Volcano Rock"),
                    ("fern-flag", "Fern Flag"),
                    ("pterosaur-wing", "Pterosaur Wing"),
                    ("dig-site-map", "Dig Site Map"),
                    ("mammoth-tooth", "Mammoth Tooth"),
                    ("dino-binoculars", "Dino Binoculars"),
                    ("canyon-rope", "Canyon Rope"),
                    ("river-raft", "River Raft"),
                    ("cave-lantern", "Cave Lantern"),
                    ("meteor-medal", "Meteor Medal"),
                ]
            )
                + Self.milestones(
                    world: .dinoDiscovery,
                    values: [
                        ("hatchery", "Dinosaur Hatchery", 3),
                        ("fossil-lab", "Fossil Lab", 8),
                        ("jungle-base", "Jungle Base", 15),
                        ("dino-parade", "Dino Parade", 25),
                        ("lost-valley", "Lost Valley", 40),
                    ]
                ),
            .firehouseHeroes: Self.smallItems(
                world: .firehouseHeroes,
                values: [
                    ("little-fire-engine", "Little Fire Engine"),
                    ("shiny-helmet", "Shiny Helmet"),
                    ("rescue-ladder", "Rescue Ladder"),
                    ("water-hose", "Water Hose"),
                    ("safety-cone", "Safety Cone"),
                    ("brave-badge", "Brave Badge"),
                    ("station-bell", "Station Bell"),
                    ("rescue-flashlight", "Rescue Flashlight"),
                    ("first-aid-kit", "First Aid Kit"),
                    ("rescue-radio", "Rescue Radio"),
                    ("silver-hydrant", "Silver Hydrant"),
                    ("fire-boots", "Fire Boots"),
                    ("city-map", "City Map"),
                    ("rescue-megaphone", "Rescue Megaphone"),
                    ("rescue-rope", "Rescue Rope"),
                    ("traffic-light", "Traffic Light"),
                    ("station-toolbox", "Station Toolbox"),
                    ("safety-jacket", "Safety Jacket"),
                    ("team-flag", "Team Flag"),
                    ("dalmatian-tag", "Dalmatian Tag"),
                ]
            )
                + Self.milestones(
                    world: .firehouseHeroes,
                    values: [
                        ("fire-station", "Friendly Fire Station", 3),
                        ("rescue-route", "Rescue Route", 8),
                        ("hero-team", "Hero Team", 15),
                        ("kindness-parade", "Kindness Parade", 25),
                        ("city-star", "City Safety Star", 40),
                    ]
                ),
            .brickworkCity: Self.smallItems(
                world: .brickworkCity,
                values: [
                    ("red-block", "Red Building Block"),
                    ("blue-block", "Blue Building Block"),
                    ("yellow-gear", "Yellow Gear"),
                    ("builder-figure", "Builder Figure"),
                    ("tiny-window", "Tiny Window"),
                    ("spinning-wheel", "Spinning Wheel"),
                    ("bridge-piece", "Bridge Piece"),
                    ("rocket-block", "Rocket Block"),
                    ("castle-block", "Castle Block"),
                    ("flower-brick", "Flower Brick"),
                    ("robot-head", "Robot Head"),
                    ("treasure-box", "Treasure Box"),
                    ("rainbow-tiles", "Rainbow Tiles"),
                    ("train-piece", "Train Piece"),
                    ("tree-brick", "Tree Brick"),
                    ("door-piece", "Door Piece"),
                    ("flag-pole", "Flag Pole"),
                    ("crane-block", "Crane Block"),
                    ("boat-build", "Boat Build"),
                    ("idea-tile", "Idea Tile"),
                ]
            )
                + Self.milestones(
                    world: .brickworkCity,
                    values: [
                        ("cozy-house", "Cozy Block House", 3),
                        ("speedy-car", "Speedy Block Car", 8),
                        ("inventor-fair", "Inventor Fair", 15),
                        ("whole-planet", "Build-a-Planet", 25),
                        ("bright-city", "Bright Block City", 40),
                    ]
                ),
            .frostlightWorld: Self.smallItems(
                world: .frostlightWorld,
                values: [
                    ("snowflake-charm", "Snowflake Charm"),
                    ("crystal-star", "Crystal Star"),
                    ("ice-skates", "Ice Skates"),
                    ("polar-mittens", "Polar Mittens"),
                    ("snowy-lantern", "Snowy Lantern"),
                    ("penguin-scarf", "Penguin Scarf"),
                    ("sled-bell", "Sled Bell"),
                    ("ice-crown", "Ice Crown"),
                    ("frost-boots", "Frost Boots"),
                    ("crystal-compass", "Crystal Compass"),
                    ("snow-globe", "Snow Globe"),
                    ("hot-cocoa", "Hot Cocoa"),
                    ("aurora-ribbon", "Aurora Ribbon"),
                    ("icicle-wand", "Icicle Wand"),
                    ("polar-map", "Polar Map"),
                    ("winter-cape", "Winter Cape"),
                    ("ice-castle-key", "Ice Castle Key"),
                    ("moon-snowball", "Moon Snowball"),
                    ("frozen-flower", "Frozen Flower"),
                    ("northern-gem", "Northern Gem"),
                ]
            )
                + Self.milestones(
                    world: .frostlightWorld,
                    values: [
                        ("snowflake-garden", "Snowflake Garden", 3),
                        ("winter-lodge", "Winter Lodge", 8),
                        ("crystal-mountain", "Crystal Mountain", 15),
                        ("snow-cloud-parade", "Snow Cloud Parade", 25),
                        ("frostlight-sunrise", "Frostlight Sunrise", 40),
                    ]
                ),
            .coasterCarnival: Self.smallItems(
                world: .coasterCarnival,
                values: [
                    ("golden-ticket", "Golden Ticket"),
                    ("rocket-car", "Rocket Coaster Car"),
                    ("loop-badge", "Loop-the-Loop Badge"),
                    ("ferris-light", "Ferris Wheel Light"),
                    ("carousel-crown", "Carousel Crown"),
                    ("popcorn-cup", "Popcorn Cup"),
                    ("balloon-bundle", "Balloon Bundle"),
                    ("prize-bear", "Prize Bear"),
                    ("funhouse-mirror", "Funhouse Mirror"),
                    ("park-map", "Park Map"),
                    ("safety-bar", "Safety Bar"),
                    ("coaster-camera", "Coaster Camera"),
                    ("parade-flag", "Parade Flag"),
                    ("cotton-candy", "Cotton Candy"),
                    ("game-token", "Game Token"),
                    ("arcade-star", "Arcade Star"),
                    ("spin-ride", "Spin Ride"),
                    ("splash-boat", "Splash Boat"),
                    ("firework-pin", "Firework Pin"),
                    ("party-hat", "Party Hat"),
                ]
            )
                + Self.milestones(
                    world: .coasterCarnival,
                    values: [
                        ("ticket-gate", "Carnival Ticket Gate", 3),
                        ("sky-train", "Carnival Sky Train", 8),
                        ("giant-coaster", "Giant Coaster", 15),
                        ("balloon-festival", "Balloon Festival", 25),
                        ("night-spectacular", "Night Spectacular", 40),
                    ]
                ),
        ]
        itemsByWorld = RewardIconCatalog.applyingIcons(to: baseItems)
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
