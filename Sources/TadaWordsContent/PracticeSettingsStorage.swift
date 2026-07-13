import TadaWordsDomain

enum PracticeSettingsStorageValidationError: Error, Equatable, Sendable {
    case duplicateProfileID(ProfileID)
}

/// Value-semantic storage shared by volatile and durable repository adapters.
struct PracticeSettingsStorage: Sendable {
    private var settingsByProfileID: [ProfileID: ProfilePracticeSettings]

    init() {
        settingsByProfileID = [:]
    }

    init(settings: [ProfilePracticeSettings]) throws {
        var indexedSettings: [ProfileID: ProfilePracticeSettings] = [:]
        indexedSettings.reserveCapacity(settings.count)

        for profileSettings in settings {
            guard indexedSettings[profileSettings.profileID] == nil else {
                throw PracticeSettingsStorageValidationError.duplicateProfileID(
                    profileSettings.profileID
                )
            }
            indexedSettings[profileSettings.profileID] = profileSettings
        }

        settingsByProfileID = indexedSettings
    }

    var settingsInStableOrder: [ProfilePracticeSettings] {
        settingsByProfileID.values.sorted {
            $0.profileID.rawValue.uuidString
                < $1.profileID.rawValue.uuidString
        }
    }

    func settings(for profileID: ProfileID) -> ProfilePracticeSettings? {
        settingsByProfileID[profileID]
    }

    @discardableResult
    mutating func save(_ settings: ProfilePracticeSettings) -> Bool {
        guard settingsByProfileID[settings.profileID] != settings else {
            return false
        }
        settingsByProfileID[settings.profileID] = settings
        return true
    }

    @discardableResult
    mutating func delete(for profileID: ProfileID) -> Bool {
        settingsByProfileID.removeValue(forKey: profileID) != nil
    }
}
