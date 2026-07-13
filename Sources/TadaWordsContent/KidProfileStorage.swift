import Foundation
import TadaWordsDomain

enum KidProfileStorageValidationError: Error, Equatable, Sendable {
    case duplicateProfileID(ProfileID)
}

/// Value-semantic storage shared by volatile and durable repository adapters.
struct KidProfileStorage: Sendable {
    private var profilesByID: [ProfileID: KidProfile]

    init() {
        profilesByID = [:]
    }

    init(profiles: [KidProfile]) throws {
        var indexedProfiles: [ProfileID: KidProfile] = [:]
        indexedProfiles.reserveCapacity(profiles.count)

        for profile in profiles {
            guard indexedProfiles[profile.id] == nil else {
                throw KidProfileStorageValidationError.duplicateProfileID(
                    profile.id
                )
            }
            indexedProfiles[profile.id] = profile
        }

        profilesByID = indexedProfiles
    }

    var profilesInStableOrder: [KidProfile] {
        profilesByID.values.sorted(by: Self.isOrderedBefore)
    }

    func profile(id: ProfileID) -> KidProfile? {
        profilesByID[id]
    }

    @discardableResult
    mutating func save(_ profile: KidProfile) throws -> Bool {
        guard let existing = profilesByID[profile.id] else {
            profilesByID[profile.id] = profile
            return true
        }
        guard existing != profile else { return false }
        guard existing.createdAt == profile.createdAt else {
            throw KidProfileRepositoryError.conflictingCreatedAt(
                profileID: profile.id,
                existing: existing.createdAt,
                incoming: profile.createdAt
            )
        }

        profilesByID[profile.id] = profile
        return true
    }

    @discardableResult
    mutating func delete(id: ProfileID) -> Bool {
        profilesByID.removeValue(forKey: id) != nil
    }

    private static func isOrderedBefore(
        _ lhs: KidProfile,
        _ rhs: KidProfile
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}
