//
//  NewVMFlow.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class NewVMFlow {
    static let sizeRange = 1...16_384  // GiB
    static let packageType = UTType(exportedAs: "com.example.quickvirtual.vm")
    
    var sizeGiB = 20
    var isAskingSize = false
    private(set) var isCreating = false
    var alertMessage: String?
    
    @ObservationIgnored private var iso: URL?
    @ObservationIgnored private var reaskSizeAfterAlert = false
    
    /// 1. ISO → 2. size sheet.
    func start() {
        guard let iso = ISOPicker.choose() else { return }
        self.iso = iso
        isAskingSize = true
    }
    
    /// 3. Save panel → free-space check → 4. create → 5. open + boot.
    func confirmSize() {
        isAskingSize = false
        // Let the sheet finish dismissing before running a modal panel.
        Task { await saveAndCreate() }
    }
    
    func alertDismissed() {
        if reaskSizeAfterAlert {
            reaskSizeAfterAlert = false
            isAskingSize = true
        }
    }
    
    private func saveAndCreate() async {
        guard let iso, let destination = chooseDestination() else { return }
        
        do {
            try PackageCreator.checkFreeSpace(
                sizeGiB: sizeGiB, at: destination.deletingLastPathComponent())
        } catch {
            reaskSizeAfterAlert = true
            alertMessage = error.localizedDescription
            return
        }
        
        isCreating = true
        defer { isCreating = false }
        do {
            let layout = try await PackageCreator.createInBackground(
                at: destination, sizeGiB: sizeGiB)
            let (document, _) = try await NSDocumentController.shared.openDocument(
                withContentsOf: layout.root, display: true)
            (document as? VMDocument)?.controller.install(iso: iso)
            self.iso = nil
        } catch {
            alertMessage = error.localizedDescription
        }
    }
    
    private func chooseDestination() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Virtual Machine"
        panel.allowedContentTypes = [Self.packageType]
        panel.nameFieldStringValue = "MyVM.quickvm"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
