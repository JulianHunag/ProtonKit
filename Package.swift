// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ProtonKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProtonCore", targets: ["ProtonCore"]),
        .executable(name: "ProtonKit", targets: ["ProtonKit"]),
        .executable(name: "TestRunner", targets: ["TestRunner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        .package(url: "https://github.com/krzyzanowskim/ObjectivePGP.git", from: "0.99.4"),
    ],
    targets: [
        .target(
            name: "ProtonCore",
            dependencies: ["BigInt", "ObjectivePGP"],
            path: "Sources/ProtonCore"
        ),
        .executableTarget(
            name: "ProtonKit",
            dependencies: ["ProtonCore"],
            path: "Sources/ProtonKit"
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["ProtonCore"],
            path: "Sources/TestRunner"
        ),
    ]
)
