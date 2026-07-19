import Foundation
import TadaWordsDomain

/// Independently mergeable Profile setting groups. Each group is transported
/// under its own stable record name so an offline audio change cannot replace
/// an unrelated Read, Write, notification, interface, or word-policy edit.
public enum PracticeSettingsSyncGroup: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case read
    case write
    case audio
    case notifications
    case interface
    case wordPolicy

    public func recordName(for profileID: ProfileID) -> String {
        "practice-settings-\(profileID)-\(rawValue)"
    }
}

public enum PracticeSettingsSyncValue: Codable, Equatable, Sendable {
    case read(LearningRouteSettings)
    case write(LearningRouteSettings)
    case audio(AudioPreferences)
    case notifications(LearningNotificationPreferences)
    case interface(PracticeInterfacePreferences)
    case wordPolicy(WordRecommendationMode)

    public var group: PracticeSettingsSyncGroup {
        switch self {
        case .read: .read
        case .write: .write
        case .audio: .audio
        case .notifications: .notifications
        case .interface: .interface
        case .wordPolicy: .wordPolicy
        }
    }

    private enum CodingKeys: String, CodingKey {
        case group
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let group = try container.decode(
            PracticeSettingsSyncGroup.self,
            forKey: .group
        )
        self =
            switch group {
            case .read:
                .read(try container.decode(LearningRouteSettings.self, forKey: .value))
            case .write:
                .write(try container.decode(LearningRouteSettings.self, forKey: .value))
            case .audio:
                .audio(try container.decode(AudioPreferences.self, forKey: .value))
            case .notifications:
                .notifications(
                    try container.decode(
                        LearningNotificationPreferences.self,
                        forKey: .value
                    )
                )
            case .interface:
                .interface(
                    try container.decode(
                        PracticeInterfacePreferences.self,
                        forKey: .value
                    )
                )
            case .wordPolicy:
                .wordPolicy(
                    try container.decode(WordRecommendationMode.self, forKey: .value)
                )
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(group, forKey: .group)
        switch self {
        case .read(let value), .write(let value):
            try container.encode(value, forKey: .value)
        case .audio(let value):
            try container.encode(value, forKey: .value)
        case .notifications(let value):
            try container.encode(value, forKey: .value)
        case .interface(let value):
            try container.encode(value, forKey: .value)
        case .wordPolicy(let value):
            try container.encode(value, forKey: .value)
        }
    }
}

public struct PracticeSettingsSyncPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profileID: ProfileID
    public let value: PracticeSettingsSyncValue

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        profileID: ProfileID,
        value: PracticeSettingsSyncValue
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.value = value
    }

    public init(
        settings: ProfilePracticeSettings,
        group: PracticeSettingsSyncGroup
    ) {
        let value: PracticeSettingsSyncValue
        switch group {
        case .read: value = .read(settings.read)
        case .write: value = .write(settings.write)
        case .audio: value = .audio(settings.audio)
        case .notifications: value = .notifications(settings.notifications)
        case .interface: value = .interface(settings.interface)
        case .wordPolicy: value = .wordPolicy(settings.wordRecommendationMode)
        }
        self.init(profileID: settings.profileID, value: value)
    }

    public var group: PracticeSettingsSyncGroup { value.group }

    public func applying(
        to current: ProfilePracticeSettings
    ) throws -> ProfilePracticeSettings {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PracticeSettingsSyncPayloadError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        guard profileID == current.profileID else {
            throw PracticeSettingsSyncPayloadError.profileMismatch
        }

        return switch value {
        case .read(let read):
            settings(from: current, read: read)
        case .write(let write):
            settings(from: current, write: write)
        case .audio(let audio):
            settings(from: current, audio: audio)
        case .notifications(let notifications):
            settings(from: current, notifications: notifications)
        case .interface(let interface):
            settings(from: current, interface: interface)
        case .wordPolicy(let wordPolicy):
            settings(from: current, wordPolicy: wordPolicy)
        }
    }

    private func settings(
        from current: ProfilePracticeSettings,
        read: LearningRouteSettings? = nil,
        write: LearningRouteSettings? = nil,
        audio: AudioPreferences? = nil,
        notifications: LearningNotificationPreferences? = nil,
        interface: PracticeInterfacePreferences? = nil,
        wordPolicy: WordRecommendationMode? = nil
    ) -> ProfilePracticeSettings {
        ProfilePracticeSettings(
            profileID: current.profileID,
            read: read ?? current.read,
            write: write ?? current.write,
            audio: audio ?? current.audio,
            notifications: notifications ?? current.notifications,
            interface: interface ?? current.interface,
            wordRecommendationMode: wordPolicy ?? current.wordRecommendationMode
        )
    }
}

public enum PracticeSettingsSyncPayloadError: Error, Equatable, Sendable {
    case profileMismatch
    case unsupportedSchemaVersion(Int)
}
