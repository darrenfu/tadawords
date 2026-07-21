public struct StarterProfileAvatar: Identifiable, Hashable, Sendable {
    public static let zodiac: [StarterProfileAvatar] = [
        StarterProfileAvatar(
            id: "rat",
            name: "Rat",
            imageAssetName: "ZodiacRat",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "ox",
            name: "Ox",
            imageAssetName: "ZodiacOx",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "tiger",
            name: "Tiger",
            imageAssetName: "ZodiacTiger",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "rabbit",
            name: "Rabbit",
            imageAssetName: "ZodiacRabbit",
            fallbackSystemImageName: "hare.fill"
        ),
        StarterProfileAvatar(
            id: "dragon",
            name: "Dragon",
            imageAssetName: "ZodiacDragon",
            fallbackSystemImageName: "lizard.fill"
        ),
        StarterProfileAvatar(
            id: "snake",
            name: "Snake",
            imageAssetName: "ZodiacSnake",
            fallbackSystemImageName: "lizard.fill"
        ),
        StarterProfileAvatar(
            id: "horse",
            name: "Horse",
            imageAssetName: "ZodiacHorse",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "goat",
            name: "Goat",
            imageAssetName: "ZodiacGoat",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "monkey",
            name: "Monkey",
            imageAssetName: "ZodiacMonkey",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "rooster",
            name: "Rooster",
            imageAssetName: "ZodiacRooster",
            fallbackSystemImageName: "bird.fill"
        ),
        StarterProfileAvatar(
            id: "dog",
            name: "Dog",
            imageAssetName: "ZodiacDog",
            fallbackSystemImageName: "dog.fill"
        ),
        StarterProfileAvatar(
            id: "pig",
            name: "Pig",
            imageAssetName: "ZodiacPig",
            fallbackSystemImageName: "pawprint.fill"
        ),
    ]

    public static let legacy: [StarterProfileAvatar] = [
        StarterProfileAvatar(
            id: "hare",
            name: "Bunny",
            fallbackSystemImageName: "hare.fill"
        ),
        StarterProfileAvatar(
            id: "fox",
            name: "Fox",
            fallbackSystemImageName: "pawprint.fill"
        ),
        StarterProfileAvatar(
            id: "bear",
            name: "Bear",
            fallbackSystemImageName: "teddybear.fill"
        ),
        StarterProfileAvatar(
            id: "owl",
            name: "Owl",
            fallbackSystemImageName: "bird.fill"
        ),
        StarterProfileAvatar(
            id: "cat",
            name: "Cat",
            fallbackSystemImageName: "cat.fill"
        ),
    ]

    public static let supported = zodiac + legacy

    public let id: String
    public let name: String
    public let imageAssetName: String?
    public let fallbackSystemImageName: String

    public init(
        id: String,
        name: String,
        imageAssetName: String? = nil,
        fallbackSystemImageName: String
    ) {
        self.id = id
        self.name = name
        self.imageAssetName = imageAssetName
        self.fallbackSystemImageName = fallbackSystemImageName
    }

    public static func option(for assetID: String) -> StarterProfileAvatar? {
        supported.first(where: { $0.id == assetID })
    }
}

extension ProfileAvatar {
    public var starterProfileAvatar: StarterProfileAvatar? {
        guard case .cartoonAnimal(let assetID) = self else { return nil }
        return StarterProfileAvatar.option(for: assetID)
    }
}
