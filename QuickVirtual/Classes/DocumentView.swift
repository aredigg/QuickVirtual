//
//  DocumentView.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Virtualization

struct DocumentView: View {
    @Bindable var controller: VMController
    
    var body: some View {
        VStack(spacing: 0) {
            VMDisplay(vm: controller.vm)
                .frame(minWidth: 640, minHeight: 400)
            
            HStack {
                if let phase = controller.shutdownPhase {
                    ProgressView().controlSize(.small)
                    Text(phase.message).font(.callout)
                } else if let notice = controller.notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.showsSecureBootEscape {
                    Button("Retry without Secure Boot") {
                        controller.turnOffSecureBoot()
                        installAction()
                    }
                }
                primaryButton
            }
            .padding(8)
        }
        .alert(
            "Virtual Machine Error",
            isPresented: Binding(
                get: { controller.alertMessage != nil },
                set: { if !$0 { controller.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.alertMessage ?? "")
        }
    }
    
    @ViewBuilder private var primaryButton: some View {
        switch controller.state {
        case .needsInstall:
            Button("Install…", action: installAction)
                .keyboardShortcut(.defaultAction)
        case .installed:
            Button("Run", action: controller.run)
                .keyboardShortcut(.defaultAction)
        case .installing:
            Button("Installing…") {}.disabled(true)
        case .running:
            Button(controller.shutdownPhase == nil ? "Running" : "Shutting Down…") {}.disabled(true)
        }
    }
    
    /// Aborted install: reuse disk, re-prompt only for the ISO (§7).
    private func installAction() {
        if let iso = ISOPicker.choose() { controller.install(iso: iso) }
    }
}

enum ISOPicker {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Installer Image"
        panel.allowedContentTypes =
        [.diskImage]
        + ["iso", "img"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct VMDisplay: NSViewRepresentable {
    let vm: VZVirtualMachine?
    
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true
        return view
    }
    
    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        if view.virtualMachine !== vm { view.virtualMachine = vm }
    }
}
