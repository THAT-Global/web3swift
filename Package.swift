// swift-tools-version: 5.9.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// THAT fork. `localTests` and `remoteTests` have not compiled since the contracts
// rewrite: 29 files reference removed APIs (`Web3.new(url)`, `ethInstance`,
// `InfuraGoerliWeb3`, …) and most need a local node. Porting them is owed as its
// own act. Until then, setting WEB3SWIFT_CORE_TESTS_ONLY drops those two targets so
// the Web3Core-only suite can build and run:
//
//     WEB3SWIFT_CORE_TESTS_ONLY=1 swift test --parallel --filter Web3CoreTests
//
// Without the variable the manifest is exactly upstream's shape plus `Web3CoreTests`.
let coreTestsOnly = ProcessInfo.processInfo.environment["WEB3SWIFT_CORE_TESTS_ONLY"] != nil

let legacyTestTargets: [Target] = [
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
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
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
        // THAT fork: offline tests over Web3Core alone (ABI head/tail bookkeeping,
        // typed custom-error decoding). Runnable today via the gate above.
        .testTarget(
            name: "Web3CoreTests",
            dependencies: ["Web3Core", "BigInt", "CryptoSwift"],
            path: "Tests/Web3CoreTests"
        )
    ] + (coreTestsOnly ? [] : legacyTestTargets)
)
