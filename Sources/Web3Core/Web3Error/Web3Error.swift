//
//  Web3Error.swift
//  Created by Yaroslav Yashin on 11.07.2022.
//

import Foundation

public enum Web3Error: LocalizedError {
    case clientError(code: Int)
    case connectionError
    case contractError(desc: String)
    case dataError
    case generalError(err: Error)
    case inputError(desc: String)
    case keystoreError(err: AbstractKeystoreError)
    case nodeError(desc: String)
    case processingError(desc: String)
    case revert(String, reason: String?)
    case revertCustom(String, [String: Any])
    case rpcError(JsonRpcErrorObject.RpcError)
    case serverError(code: Int)
    case timeoutError(desc: String)
    case transactionSerializationError
    case typeError
    case unknownError
    case valueError(desc: String? = nil)
    case walletError
    
    public var errorDescription: String? {
        switch self {
            case .clientError(let code):
                return "Client error: \(code)"
            case .connectionError:
                return "Connection Error"
            case .contractError(let desc):
                return desc
            case .dataError:
                return "Data Error"
            case .generalError(let err):
                return err.localizedDescription
            case .inputError(let desc):
                return desc
            case .keystoreError(let err):
                return err.localizedDescription
            case .nodeError(let desc):
                return desc
            case .processingError(let desc):
                return desc
            case .revert(let message, let reason):
                return "\(message); reverted with reason string: \(reason ?? "")"
            case .revertCustom(let error, _):
                return "reverted with custom error: \(error)"
            case .rpcError(let error):
                return error.message
            case .serverError(let code):
                return "Server error: \(code)"
            case .timeoutError(let desc):
                return desc
            case .transactionSerializationError:
                return "Transaction Serialization Error"
            case .typeError:
                return "Unsupported type"
            case .unknownError:
                return "Unknown Error"
            case .valueError(let errorDescription):
                return errorDescription.map { $0 } ?? "You're passing value that isn't supported by this method"
            case .walletError:
                return "Wallet Error"
        }
    }
}
