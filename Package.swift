// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "xctidy",
    products: [
        .executable(name: "xctidy", targets: ["xctidy"])
    ],
    dependencies: [
        // Test-only: lets one spec be a *real* Quick describe/context/it spec so swift test produces a genuine comma-flattened name to disambiguate, not just a hand-built fixture. See docs/COMMENTS.md.
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
    ],
    targets: [
        // Own target so the test target can @testable import it without .executableTarget's testability caveats. See docs/COMMENTS.md.
        .target(name: "XctidyKit"),

        .executableTarget(
            name: "xctidy",
            dependencies: ["XctidyKit"]
        ),

        .testTarget(
            name: "XctidyKitTests",
            dependencies: [
                "XctidyKit",
                .product(name: "Quick", package: "Quick"),
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
    ]
)
