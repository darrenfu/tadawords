import TadaWordsDomain

/// Stable SF Symbol artwork for every treasure. Arrays follow the matching
/// world's catalog order so adding a reward requires adding its artwork in the
/// same change. Symbols are unique inside each world to keep the collection
/// visually scannable for young children.
enum RewardIconCatalog {
    static func applyingIcons(
        to itemsByWorld: [WorldTheme: [RewardCatalogItem]]
    ) -> [WorldTheme: [RewardCatalogItem]] {
        Dictionary(
            uniqueKeysWithValues: itemsByWorld.map { world, items in
                let iconAssetIDs = icons(for: world)
                precondition(
                    items.count == iconAssetIDs.count,
                    "Every treasure needs exactly one stable icon"
                )
                return (
                    world,
                    zip(items, iconAssetIDs).map { item, iconAssetID in
                        RewardCatalogItem(
                            id: item.id,
                            world: item.world,
                            displayName: item.displayName,
                            iconAssetID: iconAssetID,
                            tier: item.tier,
                            requiredTodayQuestCount: item.requiredTodayQuestCount
                        )
                    }
                )
            })
    }

    static func icons(for world: WorldTheme) -> [String] {
        switch world {
        case .moonpetalKingdom:
            [
                "crown.fill", "cloud.fill", "light.ribbon.fill", "shoeprints.fill",
                "lamp.table.fill", "building.columns.fill", "wand.and.sparkles", "wind",
                "sun.max.fill", "camera.macro", "music.note", "book.closed.fill",
                "mirror.side.left", "bird.fill", "hands.clap.fill", "key.fill",
                "birthday.cake.fill", "flag.fill", "rainbow", "diamond.fill",
                "leaf.fill", "music.note.list", "building.columns.circle.fill",
                "person.3.fill", "sparkles.rectangle.stack.fill",
            ]
        case .buildItBay:
            [
                "engine.combustion.fill", "building.2.fill", "car.side.fill",
                "arrow.trianglehead.2.clockwise.rotate.90", "road.lanes", "medal.fill",
                "truck.pickup.side.fill", "wrench.and.screwdriver.fill",
                "rectangle.3.group.fill", "helmet.fill", "cone.fill", "truck.box.fill",
                "shippingbox.fill", "document.fill", "light.beacon.max.fill",
                "cart.fill", "ruler.fill", "screwdriver.fill", "radio.fill",
                "square.3.layers.3d", "road.lanes.curved.left",
                "point.topleft.down.to.point.bottomright.curvepath.fill",
                "lightbulb.max.fill", "building.2.crop.circle.fill", "hammer.fill",
            ]
        case .pawsAndPines:
            [
                "pawprint.fill", "fork.knife", "water.waves", "hare.fill", "bird.fill",
                "house.fill", "location.north.fill", "leaf.fill", "shield.fill",
                "backpack.fill", "oar.2.crossed", "mug.fill", "wind.circle.fill",
                "shoe.2.fill", "map.fill", "paperplane.fill", "speaker.wave.3.fill",
                "basket.fill",
                "binoculars.fill", "lightbulb.led.fill", "figure.hiking", "tree.fill",
                "party.popper.fill", "cross.case.fill", "sparkles",
            ]
        case .dinoDiscovery:
            [
                "lizard.fill", "shield.fill", "fossil.shell.fill", "shoeprints.fill",
                "oval.portrait.fill", "triangle.fill", "diamond.fill",
                "location.north.fill", "hat.widebrim.fill", "paintbrush.fill",
                "mountain.2.fill", "leaf.fill", "bird.fill", "map.fill",
                "waveform.path.ecg", "binoculars.fill", "lasso", "water.waves",
                "flashlight.on.fill", "medal.fill", "circle.hexagonpath.fill",
                "testtube.2", "tent.2.fill", "figure.walk.motion",
                "globe.americas.fill",
            ]
        case .firehouseHeroes:
            [
                "truck.box.fill", "helmet.fill", "stairs", "water.waves", "cone.fill",
                "shield.fill", "bell.fill", "flashlight.on.fill", "cross.case.fill",
                "radio.fill", "drop.fill", "shoe.2.fill", "map.fill", "megaphone.fill",
                "lasso", "light.beacon.max.fill", "wrench.and.screwdriver.fill",
                "figure.arms.open", "flag.fill", "pawprint.fill", "building.2.fill",
                "road.lanes", "person.3.fill", "heart.circle.fill", "star.circle.fill",
            ]
        case .brickworkCity:
            [
                "cube.fill", "square.fill", "gearshape.fill", "figure.stand",
                "window.casement", "circle.circle.fill", "rectangle.3.group.fill",
                "airplane", "building.columns.fill", "camera.macro", "cpu.fill",
                "shippingbox.fill", "square.grid.3x3.fill", "tram.fill", "tree.fill",
                "door.left.hand.closed", "flag.fill", "building.2.fill", "sailboat.fill",
                "lightbulb.fill", "house.fill", "car.fill", "sparkles", "globe",
                "building.2.crop.circle.fill",
            ]
        case .frostlightWorld:
            [
                "snowflake", "star.fill", "figure.snowboarding", "hands.clap.fill",
                "lamp.table.fill", "bird.fill", "bell.fill", "crown.fill", "shoe.2.fill",
                "location.north.fill", "globe", "mug.fill", "light.ribbon.fill",
                "wand.and.sparkles", "map.fill", "wind", "key.fill", "moon.fill",
                "camera.macro", "diamond.fill", "snowflake.circle.fill",
                "house.and.flag.fill", "mountain.2.fill", "cloud.snow.fill", "sun.snow.fill",
            ]
        case .coasterCarnival:
            [
                "ticket.fill", "car.side.fill", "arrow.trianglehead.2.clockwise.rotate.90",
                "circle.hexagongrid.fill", "crown.fill", "popcorn.fill",
                "balloon.2.fill", "teddybear.fill", "mirror.side.left", "map.fill",
                "lock.open.fill", "camera.fill", "flag.fill", "cloud.fill",
                "circle.grid.cross.fill", "gamecontroller.fill", "rotate.3d.fill",
                "sailboat.fill", "fireworks", "party.popper.fill", "airplane.ticket.fill",
                "tram.fill", "mountain.2.fill", "balloon.fill", "sparkles",
            ]
        }
    }
}
