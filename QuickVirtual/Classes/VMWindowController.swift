//
//  VMWindowController.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit

final class VMWindowController: NSWindowController, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let document = document as? VMDocument,
              document.controller.isActive
                else { return true }
        guard document.controller.shutdownPhase == nil else { return false }
        
        let alert = NSAlert()
        alert.messageText = "Shut down the virtual machine?"
        alert.informativeText =
        "The guest will be asked to shut down. If it doesn't respond within "
        + "30 seconds, it will be forced off."
        alert.addButton(withTitle: "Shut Down")
        alert.addButton(withTitle: "Cancel")
        
        Task {
            guard await alert.beginSheetModal(for: sender) == .alertFirstButtonReturn
                    else { return }
            await document.controller.shutdown()
            document.close()
        }
        return false
    }
}
