//
//  Web3+ERC888.swift
//
//  Created by Anton Grigorev on 15/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// MultiDimensional Token Standard
public protocol IERC888: IERC20 {}

public final class ERC888: ERC20, IERC888 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc888ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
}
