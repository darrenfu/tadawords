import Foundation

public struct KidProfile: Codable, Hashable, Sendable {
    public let id: ProfileID
    public let displayName: String
    public let avatar: ProfileAvatar
    public let selectedWorld: WorldTheme
    /// The first world chosen for this child. It is kept separately from the
    /// active world so switching worlds never rewrites unlock history.
    public let starterWorld: WorldTheme
    /// Guardian overrides are additive; earned unlocks are derived from Today
    /// completions and never need mutable counters.
    public let guardianUnlockedWorlds: Set<WorldTheme>
    /// A child-selected earned icon. The source `avatar` remains untouched so
    /// choosing a cartoon never discards an embedded family photo.
    public let selectedCartoonIconAssetID: String?
    /// A collected treasure chosen as the child-facing avatar. Selection is
    /// validated against the profile's reward collection before persistence.
    /// The source photo or starter animal remains untouched.
    public let selectedTreasureAvatar: TreasureAvatarSelection?
    public let schoolGrade: ProfileSchoolGrade
    public let ageYears: Int?
    public let voiceprintStatus: VoiceprintEnrollmentStatus
    public let createdAt: Date
    /// Last metadata edit, used by deterministic local/cloud conflict
    /// resolution. Older snapshots decode this as `createdAt`.
    public let updatedAt: Date

    public init(
        id: ProfileID = ProfileID(),
        displayName: String,
        avatar: ProfileAvatar,
        selectedWorld: WorldTheme,
        starterWorld: WorldTheme? = nil,
        guardianUnlockedWorlds: Set<WorldTheme> = [],
        selectedCartoonIconAssetID: String? = nil,
        selectedTreasureAvatar: TreasureAvatarSelection? = nil,
        schoolGrade: ProfileSchoolGrade = .preK,
        ageYears: Int? = nil,
        voiceprintStatus: VoiceprintEnrollmentStatus = .notEnrolled,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatar = avatar
        self.selectedWorld = selectedWorld
        self.starterWorld = starterWorld ?? selectedWorld
        self.guardianUnlockedWorlds = guardianUnlockedWorlds
        self.selectedCartoonIconAssetID =
            selectedTreasureAvatar == nil
            ? selectedCartoonIconAssetID
            : nil
        self.selectedTreasureAvatar = selectedTreasureAvatar
        self.schoolGrade = schoolGrade
        self.ageYears = ageYears.map { min(18, max(2, $0)) }
        self.voiceprintStatus = voiceprintStatus
        self.createdAt = createdAt
        self.updatedAt = max(createdAt, updatedAt ?? createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatar
        case selectedWorld
        case starterWorld
        case guardianUnlockedWorlds
        case selectedCartoonIconAssetID
        case selectedTreasureAvatar
        case schoolGrade
        case ageYears
        case voiceprintStatus
        case createdAt
        case updatedAt
    }

    /// Older local snapshots predate grade and world progression. Defaults are
    /// intentionally derived from the saved active world, preserving the
    /// child's visible experience after an app update.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedWorld = try container.decode(
            WorldTheme.self,
            forKey: .selectedWorld
        )
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            id: try container.decode(ProfileID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            avatar: try container.decode(ProfileAvatar.self, forKey: .avatar),
            selectedWorld: selectedWorld,
            starterWorld: try container.decodeIfPresent(
                WorldTheme.self,
                forKey: .starterWorld
            ) ?? selectedWorld,
            guardianUnlockedWorlds: try container.decodeIfPresent(
                Set<WorldTheme>.self,
                forKey: .guardianUnlockedWorlds
            ) ?? [],
            selectedCartoonIconAssetID: try container.decodeIfPresent(
                String.self,
                forKey: .selectedCartoonIconAssetID
            ),
            selectedTreasureAvatar: try container.decodeIfPresent(
                TreasureAvatarSelection.self,
                forKey: .selectedTreasureAvatar
            ),
            schoolGrade: try container.decodeIfPresent(
                ProfileSchoolGrade.self,
                forKey: .schoolGrade
            ) ?? .preK,
            ageYears: try container.decodeIfPresent(Int.self, forKey: .ageYears),
            voiceprintStatus: try container.decodeIfPresent(
                VoiceprintEnrollmentStatus.self,
                forKey: .voiceprintStatus
            ) ?? .notEnrolled,
            createdAt: createdAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
                ?? createdAt
        )
    }

    /// Kid-facing views use this projection. Guardian editing continues to
    /// operate on `avatar`, which is the durable source photo or starter icon.
    public var displayAvatar: ProfileAvatar {
        if let selectedTreasureAvatar {
            return .treasure(
                rewardItemID: selectedTreasureAvatar.rewardItemID,
                iconAssetID: selectedTreasureAvatar.iconAssetID
            )
        }
        guard let selectedCartoonIconAssetID else { return avatar }
        return .cartoonAnimal(assetID: selectedCartoonIconAssetID)
    }
}

public struct TreasureAvatarSelection: Codable, Hashable, Sendable {
    public let rewardItemID: RewardItemID
    public let iconAssetID: String

    public init(rewardItemID: RewardItemID, iconAssetID: String) {
        self.rewardItemID = rewardItemID
        let normalizedIconAssetID = iconAssetID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.iconAssetID =
            normalizedIconAssetID.isEmpty
            ? "sparkles"
            : normalizedIconAssetID
    }
}

public enum ProfileSchoolGrade: String, Codable, CaseIterable, Hashable, Sendable {
    case preK
    case kindergarten
    case grade1
    case grade2
    case grade3

    public var displayName: String {
        switch self {
        case .preK:
            "Pre-K"
        case .kindergarten:
            "Kindergarten"
        case .grade1:
            "Grade 1"
        case .grade2:
            "Grade 2"
        case .grade3:
            "Grade 3"
        }
    }
}

public enum ProfileAvatar: Codable, Hashable, Sendable {
    case cartoonAnimal(assetID: String)
    case photo(assetID: String, source: PhotoSource)
    case treasure(rewardItemID: RewardItemID, iconAssetID: String)

    public enum PhotoSource: String, Codable, Hashable, Sendable {
        case camera
        case photoLibrary
    }
}

extension ProfileAvatar {
    private static let embeddedJPEGPrefix = "embedded-jpeg:"

    public static func embeddedPhoto(
        data: Data,
        source: PhotoSource
    ) -> ProfileAvatar {
        .photo(
            assetID: embeddedJPEGPrefix + data.base64EncodedString(),
            source: source
        )
    }

    public var embeddedPhotoData: Data? {
        guard case .photo(let assetID, _) = self,
            assetID.hasPrefix(Self.embeddedJPEGPrefix)
        else { return nil }
        return Data(
            base64Encoded: String(assetID.dropFirst(Self.embeddedJPEGPrefix.count))
        )
    }
}

public enum VoiceprintEnrollmentStatus: Codable, Hashable, Sendable {
    case notEnrolled
    case enrolled(modelVersion: String, enrolledAt: Date)
    case needsRefresh
}

/// Durable sync adapters encode this value as a `profileDeletion` tombstone so
/// another device cannot resurrect a profile after its local data is purged.
public struct ProfileDeletionTombstone: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let deletedAt: Date

    public init(profileID: ProfileID, deletedAt: Date) {
        self.profileID = profileID
        self.deletedAt = deletedAt
    }
}
