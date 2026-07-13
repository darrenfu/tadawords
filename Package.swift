// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TadaWords",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TadaWordsDomain", targets: ["TadaWordsDomain"]),
        .library(name: "TadaWordsLearning", targets: ["TadaWordsLearning"]),
        .library(name: "TadaWordsContent", targets: ["TadaWordsContent"]),
        .library(name: "TadaWordsDesignSystem", targets: ["TadaWordsDesignSystem"]),
        .library(name: "TadaWordsFeatures", targets: ["TadaWordsFeatures"]),
        .library(name: "TadaWordsGuardianFeatures", targets: ["TadaWordsGuardianFeatures"]),
        .library(name: "TadaWordsAppShell", targets: ["TadaWordsAppShell"]),
        .library(name: "TadaWordsApplePlatform", targets: ["TadaWordsApplePlatform"]),
        .executable(name: "TadaWordsPreview", targets: ["TadaWordsPreview"]),
    ],
    targets: [
        .target(name: "TadaWordsDomain"),
        .target(
            name: "TadaWordsLearning",
            dependencies: ["TadaWordsDomain"]
        ),
        .target(
            name: "TadaWordsContent",
            dependencies: [
                "TadaWordsDomain",
                "TadaWordsLearning",
            ]
        ),
        .target(name: "TadaWordsDesignSystem"),
        .target(
            name: "TadaWordsFeatures",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDomain",
                "TadaWordsLearning",
                "TadaWordsDesignSystem",
            ]
        ),
        .target(
            name: "TadaWordsGuardianFeatures",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDomain",
                "TadaWordsLearning",
                "TadaWordsDesignSystem",
            ]
        ),
        .target(
            name: "TadaWordsAppShell",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDesignSystem",
                "TadaWordsDomain",
                "TadaWordsFeatures",
                "TadaWordsGuardianFeatures",
            ]
        ),
        .target(
            name: "TadaWordsApplePlatform",
            dependencies: ["TadaWordsDomain"]
        ),
        .executableTarget(
            name: "TadaWordsPreview",
            dependencies: ["TadaWordsAppShell"]
        ),
        .testTarget(
            name: "TadaWordsDomainTests",
            dependencies: ["TadaWordsDomain"]
        ),
        .testTarget(
            name: "TadaWordsLearningTests",
            dependencies: [
                "TadaWordsDomain",
                "TadaWordsLearning",
            ]
        ),
        .testTarget(
            name: "TadaWordsContentTests",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDomain",
                "TadaWordsLearning",
            ]
        ),
        .testTarget(
            name: "TadaWordsGuardianFeaturesTests",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDomain",
                "TadaWordsGuardianFeatures",
            ]
        ),
        .testTarget(
            name: "TadaWordsFeaturesTests",
            dependencies: [
                "TadaWordsContent",
                "TadaWordsDesignSystem",
                "TadaWordsDomain",
                "TadaWordsFeatures",
                "TadaWordsLearning",
            ]
        ),
        .testTarget(
            name: "TadaWordsAppShellTests",
            dependencies: [
                "TadaWordsAppShell",
                "TadaWordsContent",
                "TadaWordsDomain",
                "TadaWordsFeatures",
                "TadaWordsGuardianFeatures",
            ]
        ),
        .testTarget(
            name: "TadaWordsApplePlatformTests",
            dependencies: [
                "TadaWordsApplePlatform",
                "TadaWordsDomain",
            ]
        ),
    ]
)
