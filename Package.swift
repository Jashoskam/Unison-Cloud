// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UnisonOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UnisonOS", targets: ["UnisonOS"])
    ],
    targets: [
        .executableTarget(
            name: "UnisonOS",
            path: ".",
            sources: [
                "UnisonOSApp.swift",
                "Models",
                "Services",
                "Views"
            ],
            swiftSettings: [
                .enableUpcomingFeature("ConciseMagicFile")
            ]
        )
    ]
)
