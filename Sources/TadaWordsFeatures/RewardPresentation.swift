import TadaWordsDomain

extension RewardCatalogItem {
    var presentationSymbol: String {
        guard iconAssetID == "sparkles" else { return iconAssetID }

        // Rewards granted by an older app version decode without an icon ID.
        // Preserve the legacy artwork for those stable item identifiers.
        return switch id.rawValue.split(separator: ".").last.map(String.init) {
        case "starlight-tiara":
            "crown.fill"
        case "cloud-carriage":
            "cloud.fill"
        case "moon-ribbon":
            "seal.fill"
        case "crystal-slippers":
            "sparkles"
        case "royal-lantern":
            "lightbulb.fill"
        case "pearl-castle":
            "building.columns.fill"
        case "golden-excavator":
            "truck.box.fill"
        case "tower-crane":
            "building.2.fill"
        case "mighty-bulldozer":
            "car.side.fill"
        case "cement-spinner":
            "arrow.triangle.2.circlepath"
        case "road-roller":
            "road.lanes"
        case "builder-badge":
            "medal.fill"
        case "fox-scout":
            "pawprint.fill"
        case "panda-picnic":
            "fork.knife"
        case "otter-slide":
            "water.waves"
        case "bunny-burrow":
            "hare.fill"
        case "owl-lantern":
            "bird.fill"
        case "bear-cabin":
            "house.fill"
        default:
            "sparkles"
        }
    }
}
