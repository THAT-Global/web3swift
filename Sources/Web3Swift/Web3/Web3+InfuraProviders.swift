//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

/// Custom Web3 HTTP provider of Infura nodes.
public final class InfuraProvider: Web3HttpProvider {
    public init(net: Network, accessToken token: String? = nil, keystoreManager manager: KeystoreManager? = nil) async throws {
        var requestURLstring = "https://" + net.name + Web3Constants.infuraHttpScheme
        requestURLstring += token ?? Web3Constants.infuraToken
        guard let providerURL = URL(string: requestURLstring) else {
            throw Web3Error.inputError(desc: "URL created with token \(token ?? "Default token - \(Web3Constants.infuraToken)") is not a valid URL: \(requestURLstring)")
        }
        super.init(url: providerURL, network: net, keystoreManager: manager)
    }
}
