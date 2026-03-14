// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ActionHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ActionHost",
            targets: ["ActionHost"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ActionHost",
            path: "Sources"
        )
    ]
)
