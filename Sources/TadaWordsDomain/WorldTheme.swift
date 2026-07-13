public enum WorldTheme: String, Codable, CaseIterable, Hashable, Sendable {
    case moonpetalKingdom
    case buildItBay
    case pawsAndPines

    public enum Category: String, Codable, Hashable, Sendable {
        case princess
        case construction
        case animals
    }

    public var category: Category {
        switch self {
        case .moonpetalKingdom:
            .princess
        case .buildItBay:
            .construction
        case .pawsAndPines:
            .animals
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
        }
    }
}
