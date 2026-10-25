//
//  PackageCreator.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import DiskImageKit
import Foundation
import Virtualization

nonisolated enum PackageCreator {
    enum Error: Swift.Error, LocalizedError {
        case alreadyExists(URL)
        case insufficientSpace(needed: Int64, available: Int64)
        
        var errorDescription: String? {
            switch self {
            case .alreadyExists(let url):
                "A file already exists at \(url.path)."
            case .insufficientSpace(let needed, let available):
                "Not enough free space: need \(needed) bytes, have \(available)."
            }
        }
    }
    
    static let bytesPerGiB: Int64 = 1 << 30
    static let blockSize = 512
    
    /// Checks the destination volume can hold the full disk capacity.
    /// (ASIF is sparse, but the guest may fill it.)
    static func checkFreeSpace(sizeGiB: Int, at directory: URL) throws {
        let values = try directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let needed = Int64(sizeGiB) * bytesPerGiB
        guard available >= needed else {
            throw Error.insufficientSpace(needed: needed, available: available)
        }
    }
    
    /// Builds a complete package. On any failure, the partial package is
    /// removed.
    static func create(
        at root: URL, sizeGiB: Int, secureBoot: Bool
    ) throws -> PackageLayout {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: root.path) else {
            throw Error.alreadyExists(root)
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let layout = PackageLayout(root: root)
        
        do {
            // 1. Sparse ASIF disk.
            let bytes = Int64(sizeGiB) * bytesPerGiB
            _ = try DiskImage(
                creating: .asif(
                    url: layout.disk,
                    blockCount: Int(bytes / Int64(blockSize)),
                    blockSize: blockSize))
            
            // 2. Machine identifier.
            let machineID = VZGenericMachineIdentifier()
            try machineID.dataRepresentation.write(
                to: layout.machineID, options: .atomic)
            
            // 3. EFI variable store (+ Secure Boot, see Step 4).
            let store = try VZEFIVariableStore(
                creatingVariableStoreAt: layout.efiVars)
            _ = store  // SB is applied by SecureBoot.sync before first boot.
            
            // 4. Config last: its presence marks a complete package.
            try ConfigStore.write(
                VMConfig(
                    installed: false,
                    formatVersion: VMConfig.currentFormatVersion,
                    diskSizeGiB: sizeGiB,
                    secureBoot: secureBoot),
                to: layout)
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
        return layout
    }
    
    /// Runs package creation (disk allocation, file writes) off the main actor.
    @concurrent
    static func createInBackground(
        at root: URL, sizeGiB: Int
    ) async throws -> PackageLayout {
        try create(at: root, sizeGiB: sizeGiB, secureBoot: true)
    }
    
}
