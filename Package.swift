// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XcodeQuery",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "xcq", targets: ["XcodeQuery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/XcodeProj.git", exact: "8.27.7"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.6.1"),
        .package(url: "https://github.com/yonaskolb/XcodeGen.git", from: "2.41.0"),
        .package(url: "https://github.com/GraphQLSwift/GraphQL.git", from: "2.0.0"),
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
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "XcodeQueryKit",
            dependencies: [
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "GraphQL", package: "GraphQL"),
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
