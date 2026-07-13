import Foundation
import TadaWordsDesignSystem
import TadaWordsDomain

extension Array where Element == KidProfile {
    static var previewProfiles: [KidProfile] {
        let createdAt = Date(timeIntervalSince1970: 0)
        return [
            KidProfile(
                displayName: "Mia",
                avatar: .cartoonAnimal(assetID: "hare"),
                selectedWorld: .moonpetalKingdom,
                createdAt: createdAt
            ),
            KidProfile(
                displayName: "Leo",
                avatar: .cartoonAnimal(assetID: "beaver"),
                selectedWorld: .buildItBay,
                createdAt: createdAt
            ),
            KidProfile(
                displayName: "Nora",
                avatar: .cartoonAnimal(assetID: "fox"),
                selectedWorld: .pawsAndPines,
                createdAt: createdAt
            ),
        ]
    }
}

extension TadaWorldTheme {
    static func from(_ domainTheme: WorldTheme) -> TadaWorldTheme {
        switch domainTheme {
        case .moonpetalKingdom:
            .moonpetal
        case .buildItBay:
            .buildItBay
        case .pawsAndPines:
            .pawsAndPines
        }
    }
}

extension ProfileAvatar {
    var presentationSymbol: String {
        switch self {
        case .cartoonAnimal(let assetID):
            switch assetID {
            case "hare":
                "hare.fill"
            case "beaver":
                "building.2.fill"
            case "bear":
                "teddybear.fill"
            case "owl":
                "bird.fill"
            case "cat":
                "cat.fill"
            case "dog":
                "dog.fill"
            default:
                "pawprint.fill"
            }
        case .photo:
            "person.crop.circle.fill"
        }
    }
}

extension LearningMode {
    var title: String {
        switch self {
        case .read:
            "Read"
        case .write:
            "Write"
        }
    }

    var instruction: String {
        switch self {
        case .read:
            "See it. Say it."
        case .write:
            "Hear it. Write it."
        }
    }
}
