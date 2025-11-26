//
//  Network+Protocol.swift
//  THAT
//
//  Custom implementation for network handling in the THAT app.
//  Created by Bailey Nahi on 06/01/2025.
//

import Foundation
import BigInt

public struct CustomNetwork: Codable, Hashable, Sendable {
    public let id: BigUInt
    public let name: String
    public let coinName: String
    public let symbol: String
    public var rpcOverride: String? = nil
    public let rpcURLs: [String] // 1...Many (1 = Primary, Others = Fallbacks)
    public var explorerURL: String? = nil
    public let decimals: Int
    
    public init(id: BigUInt, name: String, coinName: String, symbol: String, rpcOverride: String? = nil, rpcURLs: [String], explorerURL: String? = nil, decimals: Int) {
        self.id = id
        self.name = name
        self.coinName = coinName
        self.symbol = symbol
        self.rpcOverride = rpcOverride
        self.rpcURLs = rpcURLs
        self.explorerURL = explorerURL
        self.decimals = decimals
    }
}

/// Enum for the most-used EVM networks. Network ID is crucial for EIP155 support
public enum Network: CaseIterable, Hashable, Sendable {
    case Polygon
    case Ethereum
    case BinanceSmartChain
    case Optimism
    case Arbitrum
    case GnosisChain
    case Avalanche
    case zkSync
    case Base
    case Custom(CustomNetwork)
    
    public var name: String {
        switch self {
            case .Ethereum: return "Ethereum"
            case .Polygon: return "Polygon"
            case .BinanceSmartChain: return "BNB Chain"
            case .Optimism: return "Optimism"
            case .Arbitrum: return "Arbitrum"
            case .GnosisChain: return "Gnosis Chain"
            case .Avalanche: return "Avalanche"
            case .zkSync: return "zkSync"
            case .Base: return "Base"
            case .Custom(let network): return network.name
        }
    }
    
    public var coinName: String {
        switch self {
            case .Ethereum: return "Ether"
            case .Polygon: return "Polygon Ecosystem Token"
            case .BinanceSmartChain: return "BNB"
            case .Optimism: return "Ether"
            case .Arbitrum: return "Ether"
            case .GnosisChain: return "xDAI"
            case .Avalanche: return "Avalanche"
            case .zkSync: return "Ether"
            case .Base: return "Ether"
            case .Custom(let network): return network.coinName
        }
    }
    
    public var symbol: String {
        switch self {
            case .Ethereum: return "ETH"
            case .Polygon: return "POL"
            case .BinanceSmartChain: return "BNB"
            case .Optimism: return "ETH"
            case .Arbitrum: return "ETH"
            case .GnosisChain: return "xDAI"
            case .Avalanche: return "AVAX"
            case .zkSync: return "ETH"
            case .Base: return "ETH"
            case .Custom(let network): return network.symbol
        }
    }
    
    public var chainID: BigUInt {
        switch self {
            case .Arbitrum: return BigUInt(42161)
            case .Avalanche: return BigUInt(43114)
            case .Base: return BigUInt(8453)
            case .BinanceSmartChain: return BigUInt(56)
            case .Ethereum: return BigUInt(1)
            case .GnosisChain: return BigUInt(100)
            case .Optimism: return BigUInt(10)
            case .Polygon: return BigUInt(137)
            case .zkSync: return BigUInt(324)
            case .Custom(let network): return network.id
        }
    }
    
    public static let allCases: [Network] = [
        Polygon, Base, Ethereum, BinanceSmartChain, Optimism, Arbitrum, GnosisChain, Avalanche, zkSync
    ]
    public static let commonCases: [Network] = [Ethereum, Polygon, BinanceSmartChain, Optimism, Arbitrum, GnosisChain, Avalanche, zkSync]
    
    public static let defaultNetworks = [Polygon, Ethereum]
    public static let oneInchSupportedNetworks = [Arbitrum, Avalanche, Base, BinanceSmartChain, Ethereum, GnosisChain, Optimism, Polygon, zkSync]
    
    public static func fromInt(_ id: UInt) -> Network? {
        switch id {
            case 1: return .Ethereum
            case 56: return .BinanceSmartChain
            case 137: return .Polygon
            case 10: return .Optimism
            case 42161: return .Arbitrum
            case 100: return .GnosisChain
            case 43114: return .Avalanche
            case 324: return .zkSync
            case 8453: return .Base
            default: return nil
        }
    }
}

extension Network {
    /// Represents the Chain ID of the network as an integer.
    public var chainIDAsUInt: UInt {
        // Safe - 64-bit systems (iPhone 6+) Int.max = 9,223,372,036,854,775,807
        return UInt(chainID)
    }
    
    public var decimals: Int {
        switch self {
            case .Custom(let network): return network.decimals
            default: return 18
        }
    }
}

extension Network: Equatable {
    public static func ==(lhs: Network, rhs: Network) -> Bool {
        return lhs.chainID == rhs.chainID
    }
}

extension Network: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case coinName
        case symbol
        case rpcOverride
        case rpcURLs
        case decimals
        case explorerURL
    }
    
    private enum NetworkType: String, Codable {
        case Ethereum
        case Polygon
        case BinanceSmartChain
        case Optimism
        case Arbitrum
        case GnosisChain
        case Avalanche
        case zkSync
        case Base
        case Custom
    }
    
    // Encoding
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .Polygon:
                try container.encode(NetworkType.Polygon, forKey: .type)
            case .Ethereum:
                try container.encode(NetworkType.Ethereum, forKey: .type)
            case .BinanceSmartChain:
                try container.encode(NetworkType.BinanceSmartChain, forKey: .type)
            case .Optimism:
                try container.encode(NetworkType.Optimism, forKey: .type)
            case .Arbitrum:
                try container.encode(NetworkType.Arbitrum, forKey: .type)
            case .GnosisChain:
                try container.encode(NetworkType.GnosisChain, forKey: .type)
            case .Avalanche:
                try container.encode(NetworkType.Avalanche, forKey: .type)
            case .zkSync:
                try container.encode(NetworkType.zkSync, forKey: .type)
            case .Base:
                try container.encode(NetworkType.Base, forKey: .type)
            case .Custom(let network):
                try container.encode(NetworkType.Custom, forKey: .type)
                try container.encode(String(network.id), forKey: .id)
                try container.encode(network.name, forKey: .name)
                try container.encode(network.coinName, forKey: .coinName)
                try container.encode(network.symbol, forKey: .symbol)
                try container.encode(network.rpcOverride, forKey: .rpcOverride)
                try container.encode(network.rpcURLs, forKey: .rpcURLs)
                try container.encode(network.decimals, forKey: .decimals)
                try container.encode(network.explorerURL, forKey: .explorerURL)
        }
    }
    
    // Decoding
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NetworkType.self, forKey: .type)
        
        switch type {
            case .Ethereum:
                self = .Ethereum
            case .Polygon:
                self = .Polygon
            case .BinanceSmartChain:
                self = .BinanceSmartChain
            case .Optimism:
                self = .Optimism
            case .Arbitrum:
                self = .Arbitrum
            case .GnosisChain:
                self = .GnosisChain
            case .Avalanche:
                self = .Avalanche
            case .zkSync:
                self = .zkSync
            case .Base:
                self = .Base
            case .Custom:
                let idString = try container.decode(String.self, forKey: .id)
                guard let id = BigUInt(idString) else {
                    throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid BigUInt value")
                }
                let name = try container.decode(String.self, forKey: .name)
                let coinName = try container.decode(String.self, forKey: .coinName)
                let symbol = try container.decode(String.self, forKey: .symbol)
                let rpcOverride = try container.decode(String?.self, forKey: .rpcOverride)
                let rpcURLs = try container.decode([String].self, forKey: .rpcURLs)
                let decimals = try container.decode(Int.self, forKey: .decimals)
                let explorerURL = try container.decode(String?.self, forKey: .explorerURL)
                self = .Custom(CustomNetwork(id: id, name: name, coinName: coinName, symbol: symbol, rpcOverride: rpcOverride, rpcURLs: rpcURLs, explorerURL: explorerURL, decimals: decimals))
        }
    }
}
