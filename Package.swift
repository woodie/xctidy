// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "xcbeautify-fd",
    products: [
        .executable(name: "xcbeautify-fd", targets: ["xcbeautify-fd"])
    ],
    targets: [
        // Core engine: parsing + rendering. Lives in its own target so the
        // test target can `@testable import` it without the executable
        // testability caveats that come with testing a target of type
        // .executableTarget directly.
        .target(name: "XcbeautifyFDKit"),

        .executableTarget(
            name: "xcbeautify-fd",
            dependencies: ["XcbeautifyFDKit"]
        ),

        .testTarget(
            name: "XcbeautifyFDKitTests",
            dependencies: ["XcbeautifyFDKit"]
        ),
    ]
)
