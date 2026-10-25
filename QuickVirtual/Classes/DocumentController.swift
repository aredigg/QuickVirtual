//
//  DocumentController.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit

final class DocumentController: NSDocumentController {
    enum Error: Swift.Error, LocalizedError {
        case anotherVMRunning
        
        var errorDescription: String? {
            "Another virtual machine is running. Shut it down first."
        }
    }
    
    private(set) var pendingOpens = 0
    var onDocumentsChanged: (() -> Void)?
    
    override func openDocument(
        withContentsOf url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Swift.Error)?) ->
        Void
    ) {
        if let current = documents.first as? VMDocument,
           current.fileURL?.standardizedFileURL != url.standardizedFileURL
        {
            guard !current.controller.isActive else {
                completionHandler(nil, false, Error.anotherVMRunning)
                return
            }
            current.close()
        }
        pendingOpens += 1
        super.openDocument(withContentsOf: url, display: displayDocument) {
            [weak self] document, wasOpen, error in
            guard let self else { return }
            pendingOpens -= 1
            completionHandler(document, wasOpen, error)
            if error != nil { onDocumentsChanged?() }
        }
    }
    
    override func addDocument(_ document: NSDocument) {
        super.addDocument(document)
        if let url = document.fileURL { LastPackageBookmark.save(url) }
        onDocumentsChanged?()
    }
    
    override func removeDocument(_ document: NSDocument) {
        super.removeDocument(document)
        onDocumentsChanged?()
    }
}
