public enum WorldTheme: String, Codable, CaseIterable, Hashable, Sendable {
    case moonpetalKingdom
    case buildItBay
    case pawsAndPines
    case dinoDiscovery
    case firehouseHeroes
    case brickworkCity
    case frostlightWorld
    case coasterCarnival

    public enum Category: String, Codable, Hashable, Sendable {
        case princess
        case construction
        case animals
        case dinosaurs
        case rescue
        case building
        case winter
        case amusement
    }

    public var category: Category {
        switch self {
        case .moonpetalKingdom:
            .princess
        case .buildItBay:
            .construction
        case .pawsAndPines:
            .animals
        case .dinoDiscovery:
            .dinosaurs
        case .firehouseHeroes:
            .rescue
        case .brickworkCity:
            .building
        case .frostlightWorld:
            .winter
        case .coasterCarnival:
            .amusement
        }
    }

    public var displayName: String {
        switch self {
        case .moonpetalKingdom:
            "Moonpetal Kingdom"
        case .buildItBay:
            "Build-It Bay"
        case .pawsAndPines:
            "Paws & Pines"
        case .dinoDiscovery:
            "Dino Discovery"
        case .firehouseHeroes:
            "Firehouse Heroes"
        case .brickworkCity:
            "Brickwork City"
        case .frostlightWorld:
            "Frostlight World"
        case .coasterCarnival:
            "Coaster Carnival"
        }
    }
}
