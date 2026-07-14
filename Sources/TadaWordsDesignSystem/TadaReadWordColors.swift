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

/// One theme-specific, high-contrast Read word color per World. Keeping this
/// mapping in the design system makes every word in an active World visually
/// consistent; changing Worlds is the only event that changes the word color.
public enum TadaReadWordColorPalette {
    public static let cardSurface = TadaReadWordColorToken(
        id: "read-card-paper",
        red: 1.00,
        green: 0.99,
        blue: 0.96
    )

    public static func token(for world: TadaWorldID) -> TadaReadWordColorToken {
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

    private static let moonpetal =
        token("moonpetal-royal-plum", 0.30, 0.12, 0.46)

    private static let buildItBay =
        token("buildit-blueprint", 0.03, 0.23, 0.35)

    private static let pawsAndPines =
        token("paws-pine", 0.05, 0.29, 0.18)

    private static let dinoDiscovery =
        token("dino-fossil", 0.33, 0.20, 0.07)

    private static let firehouseHeroes =
        token("firehouse-engine-red", 0.48, 0.06, 0.07)

    private static let brickworkCity =
        token("brickwork-block-blue", 0.04, 0.20, 0.52)

    private static let frostlightWorld =
        token("frostlight-midnight", 0.05, 0.18, 0.42)

    private static let coasterCarnival =
        token("coaster-carnival-plum", 0.40, 0.07, 0.36)

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
