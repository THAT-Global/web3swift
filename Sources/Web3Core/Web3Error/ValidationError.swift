//
//  ValidationError.swift
//  Created by Bailey Nahi on 29/04/2025.
//

import Foundation

// A simple error type for validation errors.
public enum ValidationError: Error {
    case invalidAddress
    case invalidAmount
    case invalidBlockNumber
    case invalidContractAddress
    case invalidEventLog
    case invalidFeeAmount
    case invalidFromAddress
    case invalidKey
    case invalidToAddress
    case invalidTransactionHash
    
    case missingInputTokenContract
    case missingOutputTokenContract
    case missingInputTokenContractKey
    case missingOutputTokenContractKey
    
    case activityAlreadyExists
    case activityEventAlreadyExists
}

extension ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .invalidAddress:
                return NSLocalizedString("Invalid Address Error", comment: "ValidationError.invalidAddress")
            case .invalidAmount:
                return NSLocalizedString("The amount is invalid.", comment: "ValidationError.invalidAmount")
            case .invalidBlockNumber:
                return NSLocalizedString("The block number is invalid.", comment: "ValidationError.invalidBlockNumber")
            case .invalidContractAddress:
                return NSLocalizedString("The contract address is invalid.", comment: "ValidationError.invalidContractAddress")
            case .invalidEventLog:
                return NSLocalizedString("The event log is malformed or missing fields.", comment: "ValidationError.invalidEventLog")
            case .invalidFeeAmount:
                return NSLocalizedString("The fee amount is invalid.", comment: "ValidationError.invalidFeeAmount")
            case .invalidFromAddress:
                return NSLocalizedString("The sender address is invalid.", comment: "ValidationError.invalidFromAddress")
            case .invalidKey:
                return NSLocalizedString("The provided key is invalid.", comment: "ValidationError.invalidKey")
            case .invalidToAddress:
                return NSLocalizedString("The recipient address is invalid.", comment: "ValidationError.invalidToAddress")
            case .invalidTransactionHash:
                return NSLocalizedString("The transaction hash is invalid.", comment: "ValidationError.invalidTransactionHash")
            case .missingInputTokenContract:
                return NSLocalizedString("Missing input token contract address.", comment: "ValidationError.missingInputTokenContract")
            case .missingOutputTokenContract:
                return NSLocalizedString("Missing output token contract address.", comment: "ValidationError.missingOutputTokenContract")
            case .missingInputTokenContractKey:
                return NSLocalizedString("Missing key for input token contract.", comment: "ValidationError.missingInputTokenContractKey")
            case .missingOutputTokenContractKey:
                return NSLocalizedString("Missing key for output token contract.", comment: "ValidationError.missingOutputTokenContractKey")
            case .activityAlreadyExists:
                return NSLocalizedString("An activity with that ID already exists.", comment: "ValidationError.activityAlreadyExists")
            case .activityEventAlreadyExists:
                return NSLocalizedString("An activity event with that ID already exists.", comment: "ValidationError.activityEventAlreadyExists")
        }
    }
}
