//
//  web3swiftDecodeSolidityErrorType.swift
//  Tests
//
//  Created by JeneaVranceanu on 25/01/2022.
//  Copyright © 2022 web3swift. All rights reserved.
//

import XCTest
import Web3Swift
import Web3Core

/// Since solidity 0.8.4 a new type was introduced called `error`.
/// Contracts' ABI with this type were not decodable.
class DecodeSolidityErrorType: XCTestCase {

    func testStructuredErrorTypeDecoding() throws {
        let contractAbiWithErrorTypes = "[{\"inputs\":[{\"internalType\":\"address\",\"name\":\"from\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"disallowedAddress\",\"type\":\"address\"}],\"name\":\"NotAllowedAddress\",\"type\":\"error\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"from\",\"type\":\"address\"},{\"internalType\":\"bytes4\",\"name\":\"disallowedFunction\",\"type\":\"bytes4\"}],\"name\":\"NotAllowedFunction\",\"type\":\"error\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"from\",\"type\":\"address\"},{\"internalType\":\"string\",\"name\":\"permission\",\"type\":\"string\"}],\"name\":\"NotAuthorised\",\"type\":\"error\"}]"
        // ENS act debt A: the ABI parser lives in Web3Core — no node, no
        // `Web3` instance needed to prove an `error`-typed ABI decodes.
        let contract = try EthereumContract(contractAbiWithErrorTypes)
        XCTAssertFalse(contract.abi.isEmpty)
        XCTAssertFalse(contract.errors.isEmpty, "the `error` elements must be parsed, not dropped")
    }
}
