//
//  TxPool.swift
//  Created by Bailey Nahi on 10/08/2025.
//

import BigInt
import Foundation
import Web3Core

public final class TxPool: Sendable {
    public let provider: Web3Provider
    public init(provider: Web3Provider) { self.provider = provider }
    
    public func txPoolStatus() async throws -> TxPoolStatus {
        let response: APIResponse<TxPoolStatus> = try await APIRequest.sendRequest(with: provider, for: .getTxPoolStatus)
        return response.result
    }
    
    public func txPoolContent() async throws -> TxPoolContent {
        let response: APIResponse<TxPoolContent> = try await APIRequest.sendRequest(with: provider, for: .getTxPoolContent)
        return response.result
    }
}
