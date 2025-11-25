//
//  Eth.swift
//  Created by Bailey Nahi on 26/11/2025.
//

import Web3Core

/// Public Eth namespace.
public final class Eth: IEth {
    public let provider: Web3Provider
    public init(provider: Web3Provider) { self.provider = provider }
}
