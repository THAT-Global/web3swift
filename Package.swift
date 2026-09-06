// swift-tools-version: 5.9.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// THAT fork. `localTests` holds the PRIMITIVE suites upstream shipped — ABI
// coder, keys/keystores (BIP32/39/44), signing and transactions (RLP, EIP-1559,
// EIP-712), addresses and utilities — ported to the contracts-rewrite API
// (ENS act debt A, that-ios ENS-SEND-FLOW-ASSESSMENT.md §10). The contract-
// wrapper suites (ST20, ERC20 classes, EthereumContract, UserCases), the
// parsers THAT owns elsewhere (EIP-681/67/4361) and every `remoteTests` file
// (Infura / live networks / the retired registry-walk ENS module) were deleted
// rather than ported: nothing THAT calls is behind them. `Web3CoreTests` holds
// the fork's own additions. A plain `swift test` runs everything; the former
// WEB3SWIFT_CORE_TESTS_ONLY gate is gone.

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
        // typed custom-error decoding, the nested-tuple encoder oracle).
        .testTarget(
            name: "Web3CoreTests",
            dependencies: ["Web3Core", "BigInt", "CryptoSwift"],
            path: "Tests/Web3CoreTests"
        ),
        // The ported primitive suites (see the header). No resources: the
        // `.sol` fixtures belonged to the deleted contract-wrapper suites.
        .testTarget(
            name: "localTests",
            dependencies: ["Web3Swift"],
            path: "Tests/web3swiftTests/localTests"
        ),
    ]
)
