// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LiveAdvisor",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "LiveAdvisor", targets: ["LiveAdvisor"])
    ],
    targets: [
        .executableTarget(
            name: "LiveAdvisor",
            path: "Sources/LiveAdvisor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
