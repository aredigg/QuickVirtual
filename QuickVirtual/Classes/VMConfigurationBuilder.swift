//
//  VMConfigurationBuilder.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import DiskImageKit
import Foundation
import Virtualization

enum VMConfigurationBuilder {
    enum Error: Swift.Error, LocalizedError {
        case invalidMachineIdentifier
        
        var errorDescription: String? {
            "machine_id.bin is corrupt; the VM cannot be started."
        }
    }
    
    static func make(
        layout: PackageLayout, isoURL: URL?
    ) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        
        // 1. Platform with the persisted identity.
        let platform = VZGenericPlatformConfiguration()
        guard
            let id = VZGenericMachineIdentifier(
                dataRepresentation: try Data(contentsOf: layout.machineID))
                else { throw Error.invalidMachineIdentifier }
        platform.machineIdentifier = id
        config.platform = platform
        
        // 2. EFI with the persisted variable store (Secure Boot state lives in it).
        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = VZEFIVariableStore(url: layout.efiVars)
        config.bootLoader = bootLoader
        
        // 3. Resources.
        config.memorySize = HostResources.memorySize
        config.cpuCount = HostResources.cpuCount
        
        // 4. Storage: ASIF main disk, optional read-only installer.
        let disk = try DiskImage(opening: .open(url: layout.disk))
        var storage: [VZStorageDeviceConfiguration] = [
            VZVirtioBlockDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(diskImage: disk))
        ]
        if let isoURL {
            storage.append(
                VZUSBMassStorageDeviceConfiguration(
                    attachment: try VZDiskImageStorageDeviceAttachment(
                        url: isoURL, readOnly: true)))
        }
        config.storageDevices = storage
        
        // 5. Graphics.
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: 1280, heightInPixels: 800)
        ]
        config.graphicsDevices = [graphics]
        
        // 6. Input.
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [
            VZUSBScreenCoordinatePointingDeviceConfiguration()
        ]
        
        // 7. Network (NAT).
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [network]
        
        // 8. Entropy + balloon.
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        config.memoryBalloonDevices = [
            VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        ]
        
        // 9. Validate.
        try config.validate()
        return config
    }
}
