import SwiftUI

/// Foundational values. Feature views should consume semantic or component tokens instead.
public enum TadaPrimitiveTokens {
    public enum TouchTarget {
        public static let minimum: CGFloat = 44
    }

    public enum Spacing {
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xLarge: CGFloat = 32
        public static let xxLarge: CGFloat = 48
    }

    public enum Radius {
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 20
        public static let large: CGFloat = 30
        public static let capsule: CGFloat = 1_000
    }

    public enum Motion {
        public static let quick: Double = 0.16
        public static let standard: Double = 0.28
        public static let reaction: Double = 0.38
        public static let celebration: Double = 0.48
        public static let ambient: Double = 4.2
    }

    public enum Depth {
        public static let cardShadowRadius: CGFloat = 18
        public static let cardShadowY: CGFloat = 9
        public static let tactileLip: CGFloat = 7
    }

    public enum ColorValue {
        public static let ink = Color(red: 0.10, green: 0.13, blue: 0.22)
        public static let softInk = Color(red: 0.29, green: 0.33, blue: 0.43)
        public static let paper = Color(red: 1.00, green: 0.99, blue: 0.96)
        public static let white = Color.white
        public static let neutralSky = Color(red: 0.93, green: 0.96, blue: 1.00)
        public static let neutralPeach = Color(red: 1.00, green: 0.94, blue: 0.91)
        public static let success = Color(red: 0.20, green: 0.65, blue: 0.43)
        public static let warning = Color(red: 0.95, green: 0.52, blue: 0.16)
        public static let error = Color(red: 0.68, green: 0.16, blue: 0.22)
    }
}

public enum TadaTypography {
    public static let metricCaption = Font.system(
        .caption,
        design: .rounded,
        weight: .semibold
    )
}

public enum TadaLayoutTokens {
    public static let readCardStandardMinimumWidth: CGFloat = 520
    public static let questChromeCompactSpacing: CGFloat = 8
    public static let compactActionRailWidth: CGFloat = 104
    public static let standardActionRailWidth: CGFloat = 142
    public static let compactHeightScrollInset: CGFloat = 12
    public static let statePanelMaximumWidth: CGFloat = 440
}

public enum TadaSemanticColors {
    public static func secondaryOnSurface(for theme: TadaWorldTheme) -> Color {
        theme.ink.opacity(0.70)
    }
}

public enum TadaWorldID: String, CaseIterable, Identifiable, Sendable {
    case moonpetal
    case buildItBay
    case pawsAndPines
    case dinoDiscovery
    case firehouseHeroes
    case brickworkCity
    case frostlightWorld
    case coasterCarnival

    public var id: String { rawValue }
}

/// Semantic colors and content for one coherent reward world.
public struct TadaWorldTheme: Identifiable, Sendable {
    public let id: TadaWorldID
    public let name: String
    public let eyebrow: String
    public let primary: Color
    public let secondary: Color
    public let accent: Color
    public let backgroundTop: Color
    public let backgroundBottom: Color
    public let surface: Color
    public let ink: Color
    public let motifSymbol: String
    public let rewardName: String
    public let rewardSymbol: String
    public let rewardSymbols: [String]
    public let ground: Color
    public let sceneAccent: Color
    public let mascotName: String

    public init(
        id: TadaWorldID,
        name: String,
        eyebrow: String,
        primary: Color,
        secondary: Color,
        accent: Color,
        backgroundTop: Color,
        backgroundBottom: Color,
        surface: Color,
        ink: Color,
        motifSymbol: String,
        rewardName: String,
        rewardSymbol: String,
        rewardSymbols: [String],
        ground: Color,
        sceneAccent: Color,
        mascotName: String
    ) {
        self.id = id
        self.name = name
        self.eyebrow = eyebrow
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.surface = surface
        self.ink = ink
        self.motifSymbol = motifSymbol
        self.rewardName = rewardName
        self.rewardSymbol = rewardSymbol
        self.rewardSymbols = rewardSymbols
        self.ground = ground
        self.sceneAccent = sceneAccent
        self.mascotName = mascotName
    }
}

extension TadaWorldTheme {
    public static let moonpetal = TadaWorldTheme(
        id: .moonpetal,
        name: "Moonpetal Kingdom",
        eyebrow: "Princess world",
        primary: Color(red: 0.43, green: 0.27, blue: 0.78),
        secondary: Color(red: 0.96, green: 0.52, blue: 0.66),
        accent: Color(red: 0.26, green: 0.71, blue: 0.83),
        backgroundTop: Color(red: 0.91, green: 0.88, blue: 1.00),
        backgroundBottom: Color(red: 1.00, green: 0.90, blue: 0.94),
        surface: Color.white.opacity(0.88),
        ink: Color(red: 0.19, green: 0.13, blue: 0.35),
        motifSymbol: "moon.stars.fill",
        rewardName: "Moonflower Tiara",
        rewardSymbol: "crown.fill",
        rewardSymbols: [
            "crown.fill", "cloud.fill", "seal.fill", "sparkles", "lightbulb.fill",
            "building.columns.fill",
        ],
        ground: Color(red: 0.66, green: 0.48, blue: 0.84),
        sceneAccent: Color(red: 1.00, green: 0.82, blue: 0.46),
        mascotName: "Pip"
    )

    public static let buildItBay = TadaWorldTheme(
        id: .buildItBay,
        name: "Build-It Bay",
        eyebrow: "Construction world",
        primary: Color(red: 0.06, green: 0.33, blue: 0.47),
        secondary: Color(red: 0.98, green: 0.67, blue: 0.13),
        accent: Color(red: 0.92, green: 0.30, blue: 0.16),
        backgroundTop: Color(red: 0.77, green: 0.93, blue: 0.98),
        backgroundBottom: Color(red: 1.00, green: 0.91, blue: 0.66),
        surface: Color.white.opacity(0.90),
        ink: Color(red: 0.05, green: 0.20, blue: 0.28),
        motifSymbol: "truck.box.fill",
        rewardName: "Golden Gear",
        rewardSymbol: "gearshape.fill",
        rewardSymbols: [
            "truck.box.fill", "building.2.fill", "car.side.fill",
            "arrow.triangle.2.circlepath", "road.lanes", "medal.fill",
        ],
        ground: Color(red: 0.13, green: 0.48, blue: 0.55),
        sceneAccent: Color(red: 1.00, green: 0.79, blue: 0.23),
        mascotName: "Bolt"
    )

    public static let pawsAndPines = TadaWorldTheme(
        id: .pawsAndPines,
        name: "Paws & Pines",
        eyebrow: "Animal world",
        primary: Color(red: 0.14, green: 0.48, blue: 0.34),
        secondary: Color(red: 0.92, green: 0.42, blue: 0.31),
        accent: Color(red: 0.96, green: 0.72, blue: 0.25),
        backgroundTop: Color(red: 0.79, green: 0.94, blue: 0.85),
        backgroundBottom: Color(red: 0.98, green: 0.90, blue: 0.74),
        surface: Color.white.opacity(0.88),
        ink: Color(red: 0.08, green: 0.26, blue: 0.19),
        motifSymbol: "pawprint.fill",
        rewardName: "Firefly Acorn",
        rewardSymbol: "leaf.fill",
        rewardSymbols: [
            "pawprint.fill", "fork.knife", "water.waves", "hare.fill", "bird.fill", "house.fill",
        ],
        ground: Color(red: 0.19, green: 0.52, blue: 0.32),
        sceneAccent: Color(red: 1.00, green: 0.78, blue: 0.35),
        mascotName: "Moss"
    )

    public static let dinoDiscovery = TadaWorldTheme(
        id: .dinoDiscovery,
        name: "Dino Discovery",
        eyebrow: "Dinosaur world",
        primary: Color(red: 0.08, green: 0.39, blue: 0.29),
        secondary: Color(red: 0.59, green: 0.78, blue: 0.22),
        accent: Color(red: 0.96, green: 0.55, blue: 0.12),
        backgroundTop: Color(red: 0.73, green: 0.92, blue: 0.83),
        backgroundBottom: Color(red: 0.98, green: 0.88, blue: 0.63),
        surface: Color.white.opacity(0.88),
        ink: Color(red: 0.05, green: 0.24, blue: 0.18),
        motifSymbol: "lizard.fill",
        rewardName: "Amber Fossil",
        rewardSymbol: "fossil.shell.fill",
        rewardSymbols: [
            "fossil.shell.fill", "lizard.fill", "leaf.fill", "mountain.2.fill",
            "pawprint.fill", "sparkles",
        ],
        ground: Color(red: 0.25, green: 0.53, blue: 0.27),
        sceneAccent: Color(red: 0.97, green: 0.66, blue: 0.20),
        mascotName: "Rumble"
    )

    public static let firehouseHeroes = TadaWorldTheme(
        id: .firehouseHeroes,
        name: "Firehouse Heroes",
        eyebrow: "Rescue world",
        primary: Color(red: 0.78, green: 0.13, blue: 0.13),
        secondary: Color(red: 0.10, green: 0.43, blue: 0.70),
        accent: Color(red: 1.00, green: 0.70, blue: 0.16),
        backgroundTop: Color(red: 0.80, green: 0.93, blue: 1.00),
        backgroundBottom: Color(red: 1.00, green: 0.83, blue: 0.73),
        surface: Color.white.opacity(0.91),
        ink: Color(red: 0.30, green: 0.07, blue: 0.08),
        motifSymbol: "firetruck.fill",
        rewardName: "Hero Badge",
        rewardSymbol: "shield.fill",
        rewardSymbols: [
            "shield.fill", "firetruck.fill", "flame.fill", "drop.fill",
            "light.beacon.max.fill", "medal.fill",
        ],
        ground: Color(red: 0.39, green: 0.43, blue: 0.48),
        sceneAccent: Color(red: 1.00, green: 0.75, blue: 0.18),
        mascotName: "Ember"
    )

    public static let brickworkCity = TadaWorldTheme(
        id: .brickworkCity,
        name: "Brickwork City",
        eyebrow: "Block-building world",
        primary: Color(red: 0.08, green: 0.32, blue: 0.72),
        secondary: Color(red: 0.98, green: 0.72, blue: 0.12),
        accent: Color(red: 0.91, green: 0.24, blue: 0.18),
        backgroundTop: Color(red: 0.75, green: 0.92, blue: 0.98),
        backgroundBottom: Color(red: 1.00, green: 0.93, blue: 0.72),
        surface: Color.white.opacity(0.91),
        ink: Color(red: 0.05, green: 0.17, blue: 0.35),
        motifSymbol: "square.grid.3x3.fill",
        rewardName: "Master Builder Block",
        rewardSymbol: "shippingbox.fill",
        rewardSymbols: [
            "shippingbox.fill", "square.grid.3x3.fill", "building.2.fill",
            "hammer.fill", "paintbrush.fill", "flag.fill",
        ],
        ground: Color(red: 0.22, green: 0.52, blue: 0.66),
        sceneAccent: Color(red: 1.00, green: 0.77, blue: 0.16),
        mascotName: "Tinker"
    )

    public static let frostlightWorld = TadaWorldTheme(
        id: .frostlightWorld,
        name: "Frostlight World",
        eyebrow: "Snow-and-aurora world",
        primary: Color(red: 0.16, green: 0.38, blue: 0.67),
        secondary: Color(red: 0.32, green: 0.76, blue: 0.85),
        accent: Color(red: 0.66, green: 0.48, blue: 0.88),
        backgroundTop: Color(red: 0.77, green: 0.91, blue: 1.00),
        backgroundBottom: Color(red: 0.93, green: 0.88, blue: 1.00),
        surface: Color.white.opacity(0.89),
        ink: Color(red: 0.08, green: 0.19, blue: 0.38),
        motifSymbol: "snowflake",
        rewardName: "Aurora Crystal",
        rewardSymbol: "diamond.fill",
        rewardSymbols: [
            "diamond.fill", "snowflake", "sparkles", "mountain.2.fill",
            "moon.stars.fill", "crown.fill",
        ],
        ground: Color(red: 0.61, green: 0.78, blue: 0.90),
        sceneAccent: Color(red: 0.66, green: 0.93, blue: 0.91),
        mascotName: "Glint"
    )

    public static let coasterCarnival = TadaWorldTheme(
        id: .coasterCarnival,
        name: "Coaster Carnival",
        eyebrow: "Theme-park world",
        primary: Color(red: 0.67, green: 0.16, blue: 0.55),
        secondary: Color(red: 0.08, green: 0.49, blue: 0.76),
        accent: Color(red: 1.00, green: 0.55, blue: 0.13),
        backgroundTop: Color(red: 0.80, green: 0.90, blue: 1.00),
        backgroundBottom: Color(red: 1.00, green: 0.84, blue: 0.91),
        surface: Color.white.opacity(0.90),
        ink: Color(red: 0.30, green: 0.07, blue: 0.29),
        motifSymbol: "ticket.fill",
        rewardName: "Golden Ride Ticket",
        rewardSymbol: "ticket.fill",
        rewardSymbols: [
            "ticket.fill", "tram.fill", "balloon.2.fill", "party.popper.fill",
            "star.fill", "trophy.fill",
        ],
        ground: Color(red: 0.23, green: 0.47, blue: 0.67),
        sceneAccent: Color(red: 1.00, green: 0.72, blue: 0.16),
        mascotName: "Zip"
    )

    public static let all: [TadaWorldTheme] = [
        moonpetal,
        buildItBay,
        pawsAndPines,
        dinoDiscovery,
        firehouseHeroes,
        brickworkCity,
        frostlightWorld,
        coasterCarnival,
    ]

    public static func theme(for id: TadaWorldID) -> TadaWorldTheme {
        all.first(where: { $0.id == id }) ?? moonpetal
    }
}

/// Component-level tokens for the two learning entrances.
public struct TadaQuestEntranceTokens {
    public enum IconShape {
        case circle
        case writingTile
    }

    public let symbol: String
    public let companionSymbol: String
    public let accent: Color
    public let iconShape: IconShape

    public init(
        symbol: String,
        companionSymbol: String,
        accent: Color,
        iconShape: IconShape
    ) {
        self.symbol = symbol
        self.companionSymbol = companionSymbol
        self.accent = accent
        self.iconShape = iconShape
    }

    public static func read(in theme: TadaWorldTheme) -> TadaQuestEntranceTokens {
        TadaQuestEntranceTokens(
            symbol: "mic.fill",
            companionSymbol: "waveform",
            accent: theme.primary,
            iconShape: .circle
        )
    }

    public static func write(in theme: TadaWorldTheme) -> TadaQuestEntranceTokens {
        TadaQuestEntranceTokens(
            symbol: "pencil.line",
            companionSymbol: "speaker.wave.2.fill",
            accent: theme.secondary,
            iconShape: .writingTile
        )
    }
}
