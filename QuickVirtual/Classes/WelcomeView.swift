//
//  WelcomeView.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import AppKit
import SwiftUI

struct WelcomeView: View {
    @State private var flow = NewVMFlow()
    @State private var openError: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("QuickVirtual").font(.largeTitle)
            HStack {
                Button("New VM (Install…)", action: flow.start)
                    .keyboardShortcut(.defaultAction)
                Button("Open…", action: open)
            }
            .disabled(flow.isCreating)
            if flow.isCreating {
                ProgressView("Creating virtual machine…")
            }
        }
        .padding(40)
        .frame(width: 440)
        .sheet(isPresented: $flow.isAskingSize) {
            DiskSizeSheet(
                sizeGiB: $flow.sizeGiB,
                onCancel: { flow.isAskingSize = false },
                onConfirm: flow.confirmSize)
        }
        .alert(
            "Cannot Create Virtual Machine",
            isPresented: Binding(
                get: { flow.alertMessage != nil },
                set: { if !$0 { flow.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel, action: flow.alertDismissed)
        } message: {
            Text(flow.alertMessage ?? "")
        }
        .alert(
            "Cannot Open Virtual Machine",
            isPresented: Binding(
                get: { openError != nil },
                set: { if !$0 { openError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }
    
    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [NewVMFlow.packageType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                _ = try await NSDocumentController.shared.openDocument(
                    withContentsOf: url, display: true)
            } catch {
                openError = error.localizedDescription
            }
        }
    }
}

struct DiskSizeSheet: View {
    @Binding var sizeGiB: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    private var isValid: Bool { NewVMFlow.sizeRange.contains(sizeGiB) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disk Size").font(.headline)
            HStack {
                TextField("Size", value: $sizeGiB, format: .number)
                    .frame(width: 100)
                Stepper("GiB", value: $sizeGiB, in: NewVMFlow.sizeRange)
            }
            Text("Space is allocated only as the guest writes data.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Continue…", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
