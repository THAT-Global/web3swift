//
//  RIPEMD160_SO.swift
//
//  Created by Alexander Vlasov on 10.01.2018.
//

import Foundation
import struct BigInt.BigUInt

public extension BigUInt {
    init?(_ naturalUnits: String, _ ethereumUnits: Utilities.Units) {
        guard let value = Utilities.parseToBigUInt(naturalUnits, units: ethereumUnits) else { return nil }
        self = value
    }

    /// Big-endian 32-byte representation, zero-padded on the left.
    var uint256BE: Data {
        let bytes = serialize()
        if bytes.count >= 32 { return Data(bytes.suffix(32)) }
        return Data(repeating: 0, count: 32 - bytes.count) + bytes
    }
}

#if COCOAPODS
extension BigUInt {
    var isZero: Bool { self == 0 }
}
#endif
