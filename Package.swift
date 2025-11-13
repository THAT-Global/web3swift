// swift-tools-version: 5.9.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Web3swift",
    platforms: [
        .macOS(.v10_15), .iOS(.v13)
    ],
    products: [
        .library(name: "web3swift", targets: ["web3swift"])
    ],
    dependencies: [
        // pin secp256k1 (used by web3swift & solana-swift)
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.10.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", .upToNextMinor(from: "5.4.0")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.5.1"),
    ],
    targets: [
        .target(
            name: "Web3Core",
            dependencies: [
                "BigInt", 
                "CryptoSwift",
                .product(name: "secp256k1", package: "swift-secp256k1"),
            ]
        ),
        .target(
            name: "web3swift",
            dependencies: [
                "BigInt",
                "Web3Core",
                .product(name: "secp256k1", package: "swift-secp256k1"),
            ],
            resources: [
                .copy("./Browser/browser.js"),
                .copy("./Browser/browser.min.js"),
                .copy("./Browser/wk.bridge.min.js")
            ]
        ),
        .testTarget(
            name: "localTests",
            dependencies: ["web3swift"],
            path: "Tests/web3swiftTests/localTests",
            resources: [
                .copy("../../../TestToken/Helpers/SafeMath/SafeMath.sol"),
                .copy("../../../TestToken/Helpers/TokenBasics/ERC20.sol"),
                .copy("../../../TestToken/Helpers/TokenBasics/IERC20.sol"),
                .copy("../../../TestToken/Token/Web3SwiftToken.sol")
            ]
        ),
        .testTarget(
            name: "remoteTests",
            dependencies: ["web3swift"],
            path: "Tests/web3swiftTests/remoteTests",
            resources: [
                .copy("../../../TestToken/Helpers/SafeMath/SafeMath.sol"),
                .copy("../../../TestToken/Helpers/TokenBasics/ERC20.sol"),
                .copy("../../../TestToken/Helpers/TokenBasics/IERC20.sol"),
                .copy("../../../TestToken/Token/Web3SwiftToken.sol")
            ]
        )
    ]
)
