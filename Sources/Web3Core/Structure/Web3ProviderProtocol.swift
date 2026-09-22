//
//  Web3ProviderProtocol.swift
//
//
//  Created by Yaroslav Yashin on 11.07.2022.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Web3Provider: Sendable {
    var network: Network { get set }
    var attachedKeystoreManager: KeystoreManager? { get set }
    var policies: Policies { get set }
    var url: URL { get }
    var session: URLSession { get }
    /// PAYMENT-CONNECTIONS-PLAN.md R-C5 — headers the provider puts on EACH request it sends (its endpoint's
    /// credentials, as `Authorization`), so a session shared between providers carries none of them. Empty
    /// unless a provider says otherwise.
    var requestHeaders: [String: String] { get }
}

extension Web3Provider {
    public var requestHeaders: [String: String] { [:] }
}
