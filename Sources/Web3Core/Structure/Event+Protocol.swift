//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation
import BigInt

// FIXME: Make me work or delete
/// Protocol for generic Ethereum event parsing results
public protocol EventParserResultProtocol {
    var eventName: String {get}
    var decodedResult: [String: Any] {get}
    var contractAddress: EthereumAddress {get}
    var transactionReceipt: TransactionReceipt? {get}
    var eventLog: EventLog? {get}
}

public struct EventParserResult: EventParserResultProtocol {
    public var eventName: String
    public var transactionReceipt: TransactionReceipt?
    public var contractAddress: EthereumAddress
    public var decodedResult: [String: Any]
    public var eventLog: EventLog?
    
    public init(eventName: String, transactionReceipt: TransactionReceipt? = nil, contractAddress: EthereumAddress, decodedResult: [String: Any], eventLog: EventLog? = nil) {
        self.eventName = eventName
        self.transactionReceipt = transactionReceipt
        self.contractAddress = contractAddress
        self.decodedResult = decodedResult
        self.eventLog = eventLog
    }
}

/// Protocol for generic Ethereum event parser
public protocol EventParserProtocol {
    func parseTransaction(_ transaction: CodableTransaction) async throws -> [EventParserResultProtocol]
    func parseTransactionByHash(_ hash: Data) async throws -> [EventParserResultProtocol]
    func parseBlock(_ block: Block) async throws -> [EventParserResultProtocol]
    func parseBlockByNumber(_ blockNumber: BigUInt) async throws -> [EventParserResultProtocol]
    func parseTransactionPromise(_ transaction: CodableTransaction) async throws -> [EventParserResultProtocol]
    func parseTransactionByHashPromise(_ hash: Data) async throws -> [EventParserResultProtocol]
    func parseBlockByNumberPromise(_ blockNumber: BigUInt) async throws -> [EventParserResultProtocol]
    func parseBlockPromise(_ block: Block) async throws -> [EventParserResultProtocol]
}

// MARK: Networks Removed and Moved
/// **Enum for the most-used Ethereum networks.**
/// The `Networks` enum (renamed to `Network`), defining Ethereum networks and their chain IDs, has been moved
/// to a separate file (`Network+Protocols.swift`) for better organization.
///
/// - **Reasoning**:
///   - To avoid and simplify merge conflicts when pulling updates.
///   - To customize network handling for THAT without over-altering the library.
///
/// Note: Almost all `Networks` functionality has been preserved and extended as `Network`.

public protocol EventLoopRunnableProtocol: Sendable {
    var name: String {get}
    func functionToRun() async
}
