// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GameTranslator",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GameTranslator",
            path: "Sources",
            resources: [
                .copy("../Resources/Info.plist")
            ]
        )
    ]
)
