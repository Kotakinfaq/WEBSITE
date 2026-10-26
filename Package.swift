// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Koan",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Koan", targets: ["Koan"])
    ],
    targets: [
        .executableTarget(
            name: "Koan",
            path: "Sources/Koan"
        )
    ]
)
