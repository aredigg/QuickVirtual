//
//  PackageLayout.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation

nonisolated struct PackageLayout: Sendable {
    let root: URL
    
    var disk: URL { root.appending(path: "disk.asif") }
    var efiVars: URL { root.appending(path: "efi_vars.store") }
    var machineID: URL { root.appending(path: "machine_id.bin") }
    var config: URL { root.appending(path: "config.json") }
}

nonisolated struct VMConfig: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1
    
    var installed: Bool
    var formatVersion: Int
    var diskSizeGiB: Int
    var secureBoot: Bool
}

nonisolated enum ConfigStore {
    enum Error: Swift.Error {
        case unsupportedFormatVersion(Int)
    }
    
    static func decode(_ data: Data) throws -> VMConfig {
        let config = try JSONDecoder().decode(VMConfig.self, from: data)
        guard config.formatVersion <= VMConfig.currentFormatVersion else {
            throw Error.unsupportedFormatVersion(config.formatVersion)
        }
        return config
    }
    
    static func write(
        _ config: VMConfig, to layout: PackageLayout,
        presenter: NSFilePresenter? = nil
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        
        var writeError: Swift.Error?
        var coordError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: layout.config, options: .forReplacing, error: &coordError
        ) { url in
            do { try data.write(to: url, options: .atomic) } catch {
                writeError = error
            }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }
}
