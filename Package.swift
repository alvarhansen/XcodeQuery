// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "XcodeQuery",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "xcq", targets: ["XcodeQuery"]),
        .executable(name: "xcodequery-wasm", targets: ["XcodeQueryWasm"]),
    ],
    dependencies: [
        .package(path: "../XcodeProj"),
        .package(path: "../TauTUI"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.6.1"),
        .package(url: "https://github.com/yonaskolb/XcodeGen.git", from: "2.41.0"),
    ],
    targets: [
        .executableTarget(
            name: "XcodeQuery",
            dependencies: [
                .target(name: "XcodeQueryCLI"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "XcodeQueryCLI",
            dependencies: [
                .target(name: "XcodeQueryKit"),
                .product(name: "TauTUI", package: "TauTUI"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "XcodeQueryKit",
            dependencies: [
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .executableTarget(
            name: "XcodeQueryWasm",
            dependencies: [
                .target(name: "XcodeQueryKit"),
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "--export=xcq_alloc",
                        "-Xlinker", "--export=xcq_free",
                        "-Xlinker", "--export=xcq_last_error",
                        "-Xlinker", "--export=xcq_query_from_pbxproj_json",
                    ],
                    .when(platforms: [.wasi])
                ),
            ]
        ),
        .testTarget(
            name: "XcodeQueryKitTests",
            dependencies: [
                .target(name: "XcodeQueryKit"),
                .target(name: "XcodeQueryCLI"),
                .product(name: "XcodeGenKit", package: "XcodeGen"),
                .product(name: "ProjectSpec", package: "XcodeGen"),
            ],
            resources: [
                // Include snapshot baselines used by tests
                .process("Snapshots")
            ]
        ),
    ]
)
