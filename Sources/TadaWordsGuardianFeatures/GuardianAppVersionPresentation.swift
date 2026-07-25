import Foundation

struct GuardianAppVersionPresentation: Equatable, Sendable {
    static let accessibilityIdentifier = "guardian.app.version"

    private static let unavailableValue = "unavailable"

    let marketingVersion: String
    let buildNumber: String

    init(marketingVersion: String?, buildNumber: String?) {
        self.marketingVersion = Self.normalized(marketingVersion)
        self.buildNumber = Self.normalized(buildNumber)
    }

    init(infoDictionary: [String: Any]?) {
        self.init(
            marketingVersion: infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: infoDictionary?["CFBundleVersion"] as? String
        )
    }

    static var current: Self {
        Self(infoDictionary: Bundle.main.infoDictionary)
    }

    var footerText: String {
        switch (marketingVersion, buildNumber) {
        case (Self.unavailableValue, Self.unavailableValue):
            "Version unavailable"
        case (Self.unavailableValue, let build):
            "Version unavailable (build \(build))"
        case (let version, Self.unavailableValue):
            "Version \(version) (build unavailable)"
        case (let version, let build):
            "Version \(version) (\(build))"
        }
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else {
            return unavailableValue
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            return unavailableValue
        }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_+"
        )
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else {
            return unavailableValue
        }
        return trimmed
    }
}
