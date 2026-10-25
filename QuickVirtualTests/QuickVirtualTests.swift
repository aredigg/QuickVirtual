//
//  QuickVirtualTests.swift
//  QuickVirtualTests
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation
import Testing
import Virtualization

@testable import QuickVirtual

@Suite struct ConfigStoreTests {
  @Test func roundTrip() throws {
    let dir = try TempDir()
    let layout = PackageLayout(root: dir.url)
    let config = VMConfig(
      installed: true, formatVersion: 1, diskSizeGiB: 20, secureBoot: false)
    try ConfigStore.write(config, to: layout)
    let read = try ConfigStore.decode(Data(contentsOf: layout.config))
    #expect(read == config)
  }

  @Test func rejectsFutureFormat() throws {
    let json = Data(
      #"{"installed":false,"formatVersion":99,"diskSizeGiB":20,"secureBoot":true}"#
        .utf8)
    #expect(throws: ConfigStore.Error.self) {
      try ConfigStore.decode(json)
    }
  }
}

@Suite struct HostResourcesTests {
  @Test func memoryWithinBoundsAndAligned() {
    let mem = HostResources.memorySize
    #expect(mem >= VZVirtualMachineConfiguration.minimumAllowedMemorySize)
    #expect(mem <= VZVirtualMachineConfiguration.maximumAllowedMemorySize)
    #expect(mem % (1 << 20) == 0)
    #expect(mem <= ProcessInfo.processInfo.physicalMemory / 2
      || mem == VZVirtualMachineConfiguration.minimumAllowedMemorySize)
  }

  @Test func cpuWithinBounds() {
    let cpus = HostResources.cpuCount
    #expect(cpus >= 1)
    #expect(cpus <= VZVirtualMachineConfiguration.maximumAllowedCPUCount)
  }
}

@Suite struct PackageCreatorTests {
  @Test func createsCompleteSparsePackage() throws {
    let dir = try TempDir()
    let root = dir.url.appending(path: "Test.quickvm")
    let layout = try PackageCreator.create(
      at: root, sizeGiB: 64, secureBoot: true)

    let fm = FileManager.default
    for file in [layout.disk, layout.efiVars, layout.machineID, layout.config] {
      #expect(fm.fileExists(atPath: file.path), "\(file.lastPathComponent)")
    }

    // Sparse: allocated size far below 64 GiB capacity.
    let allocated = try layout.disk
      .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
      .totalFileAllocatedSize ?? .max
    #expect(allocated < 100 * 1024 * 1024)

    let config = try ConfigStore.decode(Data(contentsOf: layout.config))
    #expect(config.installed == false)
    #expect(config.diskSizeGiB == 64)
    #expect(config.secureBoot == true)
  }

  @Test func refusesExistingDestination() throws {
    let dir = try TempDir()
    #expect(throws: PackageCreator.Error.self) {
      try PackageCreator.create(at: dir.url, sizeGiB: 1, secureBoot: true)
    }
  }

  @Test func machineIdentifierRoundTrips() throws {
    let dir = try TempDir()
    let layout = try PackageCreator.create(
      at: dir.url.appending(path: "M.quickvm"), sizeGiB: 1, secureBoot: true)
    let data = try Data(contentsOf: layout.machineID)
    #expect(VZGenericMachineIdentifier(dataRepresentation: data) != nil)
  }
}

@Suite struct PackageLockTests {
  @Test func secondLockFails() throws {
    let dir = try TempDir()
    let first = try PackageLock(root: dir.url)
    #expect(throws: PackageLock.Error.self) {
      _ = try PackageLock(root: dir.url)
    }
    _ = first
  }
}

/// Deleted on deinit.
final class TempDir {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: url) }
}
