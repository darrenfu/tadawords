import Foundation
import SwiftUI

/// An auditable sRGB token used for the large word on a Read quest card.
public struct TadaReadWordColorToken: Identifiable, Hashable, Sendable {
    public let id: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(
        id: String,
        red: Double,
        green: Double,
        blue: Double
    ) {
        precondition((0...1).contains(red))
        precondition((0...1).contains(green))
        precondition((0...1).contains(blue))
        self.id = id
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// WCAG relative-luminance contrast for two opaque sRGB colors.
    public func contrastRatio(against other: TadaReadWordColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    private static func linearized(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}

/// Theme-specific, high-contrast word colors. Selection is stable across
/// redraws and app processes because it does not use Swift's randomized Hasher.
public enum TadaReadWordColorPalette {
    public static let cardSurface = TadaReadWordColorToken(
        id: "read-card-paper",
        red: 1.00,
        green: 0.99,
        blue: 0.96
    )

    public static func tokens(for world: TadaWorldID) -> [TadaReadWordColorToken] {
        switch world {
        case .moonpetal:
            moonpetal
        case .buildItBay:
            buildItBay
        case .pawsAndPines:
            pawsAndPines
        case .dinoDiscovery:
            dinoDiscovery
        case .firehouseHeroes:
            firehouseHeroes
        case .brickworkCity:
            brickworkCity
        case .frostlightWorld:
            frostlightWorld
        case .coasterCarnival:
            coasterCarnival
        }
    }

    public static func token(
        for world: TadaWorldID,
        stableKey: String
    ) -> TadaReadWordColorToken {
        let available = tokens(for: world)
        let hash = stableHash("\(world.rawValue)|\(stableKey)")
        return available[Int(hash % UInt64(available.count))]
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private static let moonpetal = [
        token("moonpetal-royal-plum", 0.30, 0.12, 0.46),
        token("moonpetal-storybook-berry", 0.42, 0.08, 0.27),
        token("moonpetal-twilight-blue", 0.12, 0.22, 0.50),
        token("moonpetal-magic-teal", 0.04, 0.28, 0.32),
    ]

    private static let buildItBay = [
        token("buildit-blueprint", 0.03, 0.23, 0.35),
        token("buildit-safety-rust", 0.48, 0.16, 0.05),
        token("buildit-steel-blue", 0.10, 0.28, 0.40),
        token("buildit-worksite-green", 0.08, 0.30, 0.22),
    ]

    private static let pawsAndPines = [
        token("paws-pine", 0.05, 0.29, 0.18),
        token("paws-bark", 0.32, 0.18, 0.08),
        token("paws-wild-berry", 0.45, 0.10, 0.15),
        token("paws-night-sky", 0.12, 0.22, 0.31),
    ]

    private static let dinoDiscovery = [
        token("dino-fossil", 0.33, 0.20, 0.07),
        token("dino-jungle", 0.04, 0.29, 0.15),
        token("dino-lava", 0.45, 0.10, 0.08),
        token("dino-tar-pit", 0.08, 0.22, 0.28),
    ]

    private static let firehouseHeroes = [
        token("firehouse-engine-red", 0.48, 0.06, 0.07),
        token("firehouse-hydrant-blue", 0.05, 0.22, 0.48),
        token("firehouse-smoke", 0.18, 0.19, 0.22),
        token("firehouse-rescue-maroon", 0.35, 0.08, 0.12),
    ]

    private static let brickworkCity = [
        token("brickwork-block-blue", 0.04, 0.20, 0.52),
        token("brickwork-brick-red", 0.45, 0.10, 0.07),
        token("brickwork-builder-green", 0.05, 0.28, 0.20),
        token("brickwork-imagination-plum", 0.32, 0.12, 0.35),
    ]

    private static let frostlightWorld = [
        token("frostlight-midnight", 0.05, 0.18, 0.42),
        token("frostlight-aurora", 0.02, 0.31, 0.34),
        token("frostlight-violet", 0.28, 0.16, 0.50),
        token("frostlight-polar-navy", 0.12, 0.26, 0.38),
    ]

    private static let coasterCarnival = [
        token("coaster-carnival-plum", 0.40, 0.07, 0.36),
        token("coaster-ride-blue", 0.03, 0.24, 0.50),
        token("coaster-velvet-red", 0.48, 0.08, 0.17),
        token("coaster-night-teal", 0.02, 0.29, 0.31),
    ]

    private static func token(
        _ id: String,
        _ red: Double,
        _ green: Double,
        _ blue: Double
    ) -> TadaReadWordColorToken {
        TadaReadWordColorToken(
            id: id,
            red: red,
            green: green,
            blue: blue
        )
    }
}
