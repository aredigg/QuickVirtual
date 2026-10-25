//
//  Resources.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation
import Virtualization

nonisolated enum HostResources {
    static var memorySize: UInt64 {
        let half = ProcessInfo.processInfo.physicalMemory / 2
        let lo = VZVirtualMachineConfiguration.minimumAllowedMemorySize
        let hi = VZVirtualMachineConfiguration.maximumAllowedMemorySize
        // Align down to 1 MiB, as the framework requires.
        let aligned = min(max(half, lo), hi) & ~UInt64((1 << 20) - 1)
        return max(aligned, lo)
    }
    
    static var cpuCount: Int {
        let half = ProcessInfo.processInfo.processorCount / 2
        let lo = max(VZVirtualMachineConfiguration.minimumAllowedCPUCount, 1)
        let hi = VZVirtualMachineConfiguration.maximumAllowedCPUCount
        return min(max(half, lo), hi)
    }
}
