//
//  AppDelegate.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcomeWindow: NSWindow?
    private var isTerminating = false
    private var didFinishLaunching = false
    
    private var documentController: DocumentController {
        // Created in main.swift before the app runs.
        NSDocumentController.shared as! DocumentController
    }
    
    // MARK: Launch (§4)
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        installMainMenu()
        documentController.onDocumentsChanged = { [weak self] in
            self?.documentsChanged()
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        // A Finder double-click delivers its open request before this point.
        // If one is in flight or done, don't auto-open the last package.
        guard documentController.documents.isEmpty,
              documentController.pendingOpens == 0
                else { return }
        
        guard let url = LastPackageBookmark.resolve() else {
            showWelcome()
            return
        }
        // On failure, DocumentController calls onDocumentsChanged, which
        // shows the welcome view.
        documentController.openDocument(withContentsOf: url, display: true) {
            _, _, _ in
        }
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        // The welcome window replaces the closed VM window.
        false
    }
    
    /// Dock click with no visible windows: bring the welcome window back.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, documentController.documents.isEmpty { showWelcome() }
        return true
    }
    
    // MARK: Welcome window (§9.2)
    
    private func documentsChanged() {
        guard didFinishLaunching, !isTerminating else { return }
        if documentController.documents.isEmpty,
           documentController.pendingOpens == 0
        {
            showWelcome()
        } else if !documentController.documents.isEmpty {
            // orderOut, not close: keeps the in-progress NewVMFlow state alive.
            welcomeWindow?.orderOut(nil)
        }
    }
    
    private func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "QuickVirtual"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: WelcomeView())
            window.center()
            welcomeWindow = window
        }
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }
    
    // MARK: Quit (§10.1)
    
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        let active = documentController.documents
            .compactMap { $0 as? VMDocument }
            .filter { $0.controller.isActive }
        guard !active.isEmpty else { return .terminateNow }
        
        isTerminating = true
        NSApp.activate()
        for document in active {
            for controller in document.windowControllers {
                controller.window?.deminiaturize(nil)
                controller.window?.makeKeyAndOrderFront(nil)
            }
        }
        
        Task {
            for document in active {
                await document.controller.shutdown()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    
    // MARK: Menu (About + Quit only)
    
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About QuickVirtual",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit QuickVirtual",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }
}
