//
//  SecureBoot.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Virtualization

enum SecureBoot {
    static func enable(on store: VZEFIVariableStore) throws {
        try store.enrollDefaultSecureBootSignatures()
        try store.enableSecureBootUsingDefaultPlatformKey()
    }
    
    static func disable(on store: VZEFIVariableStore) throws {
        try store.disableSecureBoot()
    }
    
    /// Makes the variable store match config.json. VM must be stopped.
    static func sync(enabled: Bool, layout: PackageLayout) throws {
        let store = VZEFIVariableStore(url: layout.efiVars)
        if enabled { try enable(on: store) } else { try disable(on: store) }
    }
}
