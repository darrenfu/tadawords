import Foundation

/// The synchronized wire shape for a Profile. Voiceprint enrollment is
/// intentionally absent: it is derived from each device's Keychain and must
/// never be exported, even as a sentinel value.
public struct FamilySyncProfilePayload: Codable, Equatable, Sendable {
    public let id: ProfileID
    public let displayName: String
    public let avatar: ProfileAvatar
    public let selectedWorld: WorldTheme
    public let starterWorld: WorldTheme
    public let guardianUnlockedWorlds: Set<WorldTheme>
    public let selectedCartoonIconAssetID: String?
    public let selectedTreasureAvatar: TreasureAvatarSelection?
    public let schoolGrade: ProfileSchoolGrade
    public let ageYears: Int?
    public let createdAt: Date
    public let updatedAt: Date

    public init(profile: KidProfile) {
        id = profile.id
        displayName = profile.displayName
        avatar = profile.avatar
        selectedWorld = profile.selectedWorld
        starterWorld = profile.starterWorld
        guardianUnlockedWorlds = profile.guardianUnlockedWorlds
        selectedCartoonIconAssetID = profile.selectedCartoonIconAssetID
        selectedTreasureAvatar = profile.selectedTreasureAvatar
        schoolGrade = profile.schoolGrade
        ageYears = profile.ageYears
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
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
        case createdAt
        case updatedAt
    }

    /// This decoder also accepts Profile payloads emitted by older builds.
    /// Codable ignores their extra `voiceprintStatus` key, while the defaults
    /// below retain the same safe migration behavior as local Profile storage.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedWorld = try container.decode(
            WorldTheme.self,
            forKey: .selectedWorld
        )
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            profile: KidProfile(
                id: try container.decode(ProfileID.self, forKey: .id),
                displayName: try container.decode(
                    String.self,
                    forKey: .displayName
                ),
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
                ageYears: try container.decodeIfPresent(
                    Int.self,
                    forKey: .ageYears
                ),
                voiceprintStatus: .notEnrolled,
                createdAt: createdAt,
                updatedAt: try container.decodeIfPresent(
                    Date.self,
                    forKey: .updatedAt
                ) ?? createdAt
            )
        )
    }

    public func replacingAvatar(_ avatar: ProfileAvatar) -> Self {
        Self(
            id: id,
            displayName: displayName,
            avatar: avatar,
            selectedWorld: selectedWorld,
            starterWorld: starterWorld,
            guardianUnlockedWorlds: guardianUnlockedWorlds,
            selectedCartoonIconAssetID: selectedCartoonIconAssetID,
            selectedTreasureAvatar: selectedTreasureAvatar,
            schoolGrade: schoolGrade,
            ageYears: ageYears,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func materialized(
        preservingVoiceprintStatus voiceprintStatus: VoiceprintEnrollmentStatus
    ) -> KidProfile {
        KidProfile(
            id: id,
            displayName: displayName,
            avatar: avatar,
            selectedWorld: selectedWorld,
            starterWorld: starterWorld,
            guardianUnlockedWorlds: guardianUnlockedWorlds,
            selectedCartoonIconAssetID: selectedCartoonIconAssetID,
            selectedTreasureAvatar: selectedTreasureAvatar,
            schoolGrade: schoolGrade,
            ageYears: ageYears,
            voiceprintStatus: voiceprintStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private init(
        id: ProfileID,
        displayName: String,
        avatar: ProfileAvatar,
        selectedWorld: WorldTheme,
        starterWorld: WorldTheme,
        guardianUnlockedWorlds: Set<WorldTheme>,
        selectedCartoonIconAssetID: String?,
        selectedTreasureAvatar: TreasureAvatarSelection?,
        schoolGrade: ProfileSchoolGrade,
        ageYears: Int?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.avatar = avatar
        self.selectedWorld = selectedWorld
        self.starterWorld = starterWorld
        self.guardianUnlockedWorlds = guardianUnlockedWorlds
        self.selectedCartoonIconAssetID = selectedCartoonIconAssetID
        self.selectedTreasureAvatar = selectedTreasureAvatar
        self.schoolGrade = schoolGrade
        self.ageYears = ageYears
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
