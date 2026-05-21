//
//  Policies.swift
//
//
//  Created by Jann Driessen on 01.11.22.
//

import Foundation
import BigInt

public typealias NoncePolicy = BlockNumber

/// Policies for resolving values like:
/// - gas required for transaction execution
/// - gas price
/// - maximum fee per gas (see [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559))
/// - maximum priority fee per gas (see [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559))
public enum ValueResolutionPolicy: Sendable {
    /// What ever value will be resolved is the one to be applied
    case automatic
    /// Specific value to be applied
    case manual(BigUInt)
}

public struct Policies: Sendable {
    public let noncePolicy: NoncePolicy
    public let gasLimitPolicy: ValueResolutionPolicy
    public let gasPricePolicy: ValueResolutionPolicy
    public let maxFeePerGasPolicy: ValueResolutionPolicy
    public let maxPriorityFeePerGasPolicy: ValueResolutionPolicy
    
    public init(
        // `.latest` (not `.pending`) is the deliberate default. A
        // user-driven retry against a tx that's still in mempool would
        // otherwise resolve to the next nonce and confirm a second
        // payment instead of colliding with the first — i.e. a retry
        // tap at a POS counter could pay the merchant twice. With
        // `.latest`, the retry uses the same nonce as the in-flight
        // tx, the node returns `already known` / `replacement
        // underpriced`, and only one confirms. We prefer that failure
        // mode over silent double-confirm. Specific call sites that
        // genuinely need mempool-aware nonces (e.g. `RewardsStore
        // +Payment.swift:620`'s permit→pay sequence) opt in by setting
        // `tx.callOnBlock = .pending` or constructing
        // `Policies(noncePolicy: .pending, ...)` explicitly — `PolicyResolver`
        // now honours both. (V202-RELEASE-AUDIT.md H-1 follow-up.)
        noncePolicy: NoncePolicy = .latest,
        gasLimitPolicy: ValueResolutionPolicy = .automatic,
        gasPricePolicy: ValueResolutionPolicy = .automatic,
        maxFeePerGasPolicy: ValueResolutionPolicy = .automatic,
        maxPriorityFeePerGasPolicy: ValueResolutionPolicy = .automatic) {
            self.noncePolicy = noncePolicy
            self.gasLimitPolicy = gasLimitPolicy
            self.gasPricePolicy = gasPricePolicy
            self.maxFeePerGasPolicy = maxFeePerGasPolicy
            self.maxPriorityFeePerGasPolicy = maxPriorityFeePerGasPolicy
        }
    
    public static var auto: Policies { Policies() }
}
