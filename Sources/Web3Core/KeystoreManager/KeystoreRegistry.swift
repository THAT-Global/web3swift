//
//  KeystoreRegistry.swift
//  THAT
//
//  Created by Bailey Nahi on 25/11/2025.
//

import Foundation

public actor KeystoreRegistry {
    public static let shared = KeystoreRegistry()
    
    private var managers: [KeystoreManager] = []
    
    // MARK: - Registration
    
    public func register(_ manager: KeystoreManager) { managers.append(manager) }
    public func unregister(_ manager: KeystoreManager) { managers.removeAll { $0 === manager } }
    
    // MARK: - Accessors
    
    public var allManagers: [KeystoreManager] { managers }
    public var defaultManager: KeystoreManager? { managers.first }
    
    // MARK: - Factory mirroring the old managerForPath(...)
    
    @discardableResult
    public func managerForPath(
        _ path: String,
        scanForHDwallets: Bool = false,
        suffix: String? = nil
    ) -> KeystoreManager? {
        guard let manager = try? KeystoreManager(path, scanForHDwallets: scanForHDwallets, suffix: suffix) else {
            return nil
        }
        managers.append(manager)
        return manager
    }
}
