// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-html-i-can-see",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "HTMLICanSee",
            targets: [
                "HTMLICanSeeTokenizer",
                "HTMLICanSeeSwiftUI",
            ]
        ),
    ],
    targets: [
        .target(
            name: "HTMLICanSeeTokenizer"
        ),
        .target(
            name: "HTMLICanSeeSwiftUI",
            dependencies: [
                "HTMLICanSeeTokenizer",
            ]
        ),
        .testTarget(
            name: "HTMLICanSeeTokenizerTests",
            dependencies: [
                "HTMLICanSeeTokenizer",
            ],
            resources: [
                .process("Fixtures"),
            ]
        ),
        .testTarget(
            name: "HTMLICanSeeSwiftUITests",
            dependencies: [
                "HTMLICanSeeSwiftUI",
                "HTMLICanSeeTokenizer",
            ],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
