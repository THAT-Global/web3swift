// swift-tools-version: 5.9.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Web3Swift",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v17)
    ],
    products: [
        .library(name: "Web3Swift", targets: ["Web3Swift"]),
        // Exposed for downstream packages that only need Web3Core's
        // pure-Swift primitives (EthereumAddress checksum, RLP, ABI) without
        // pulling in Web3Swift's HTTP + WebKit + CoreImage surface. Added for
        // wire-schema (R-7), which references EthereumAddress in Contact and
        // BizWallet.sanitized().
        .library(name: "Web3Core", targets: ["Web3Core"])
    ],
    dependencies: [
        // pin secp256k1 (used by web3swift & solana-swift)
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", exact: "0.10.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "6.0.0"),
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
            name: "Web3Swift",
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
            dependencies: ["Web3Swift"],
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
            dependencies: ["Web3Swift"],
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
