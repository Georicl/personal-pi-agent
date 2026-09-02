// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalPi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PersonalPi", targets: ["PersonalPi"])
    ],
    targets: [
        .executableTarget(
            name: "PersonalPi",
            path: "Sources/PersonalPi"
        ),
        .testTarget(
            name: "PersonalPiTests",
            dependencies: ["PersonalPi"],
            path: "Tests/PersonalPiTests"
        )
    ]
)
