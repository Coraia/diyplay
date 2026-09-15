// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "diyplay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "diyplay", targets: ["diyplay"]),
    ],
    targets: [
        .executableTarget(
            name: "diyplay",
            dependencies: ["VirtualDisplaySupport"],
            path: "Sources/diyplay",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "VirtualDisplaySupport",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        .testTarget(name: "diyplayTests", dependencies: ["diyplay"]),
    ]
)
