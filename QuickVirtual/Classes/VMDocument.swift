//
//  VMDocument.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit
import SwiftUI

final class VMDocument: NSDocument {
    enum Error: Swift.Error, LocalizedError {
        case incompletePackage(missing: String)
        
        var errorDescription: String? {
            switch self {
            case .incompletePackage(let name):
                "This VM package is incomplete (missing \(name))."
            }
        }
    }
    
    private(set) var config: VMConfig?
    private(set) lazy var controller = VMController(document: self)
    
    /// Derived from fileURL so it follows moves/renames while open.
    var layout: PackageLayout? { fileURL.map(PackageLayout.init(root:)) }
    
    // Never save, autosave, or version anything; the VM owns the contents.
    nonisolated override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var preservesVersions: Bool { false }
    
    /// Reads happen on the main thread; read(from:) relies on this.
    nonisolated override class func canConcurrentlyReadDocuments(
        ofType typeName: String
    ) -> Bool {
        false
    }
    
    nonisolated override func read(from url: URL, ofType typeName: String)
    throws
    {
        let layout = PackageLayout(root: url)
        let required = [
            layout.disk, layout.efiVars, layout.machineID, layout.config,
        ]
        for file in required
                where !FileManager.default.fileExists(atPath: file.path) {
            throw Error.incompletePackage(missing: file.lastPathComponent)
        }
        let decoded = try ConfigStore.decode(Data(contentsOf: layout.config))
        MainActor.assumeIsolated { self.config = decoded }
    }
    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }
    
    /// The only mutation path; writes config.json directly, no NSDocument save.
    func updateConfig(_ change: (inout VMConfig) -> Void) throws {
        guard var new = config, let layout else { return }
        change(&new)
        try ConfigStore.write(new, to: layout, presenter: self)
        config = new
    }
    
    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 844),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: DocumentView(controller: controller))
        window.center()
        let controller = VMWindowController(window: window)
        window.delegate = controller
        addWindowController(controller)
    }
}
