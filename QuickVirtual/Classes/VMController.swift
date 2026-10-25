//
//  VMController.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation
import Observation
import Virtualization

@Observable
final class VMController: NSObject {
    enum State: Equatable {
        case needsInstall, installing, installed, running
    }
    
    enum ShutdownPhase: Equatable {
        case requesting, forcing
        
        var message: String {
            switch self {
            case .requesting: "Shutting down — waiting for guest…"
            case .forcing: "Guest not responding — forcing off…"
            }
        }
    }
    
    private(set) var state: State
    private(set) var vm: VZVirtualMachine?
    private(set) var notice: String?
    private(set) var shutdownPhase: ShutdownPhase?
    var alertMessage: String?
    
    @ObservationIgnored private weak let document: VMDocument?
    @ObservationIgnored private var isoURL: URL?
    @ObservationIgnored private var lock: PackageLock?
    @ObservationIgnored private var bootStart: ContinuousClock.Instant?
    @ObservationIgnored private var didAutoRetry = false
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var stopWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var stopTimeoutTask: Task<Void, Never>?
    
    static let shutdownTimeout: Duration = .seconds(30)
    
    var isActive: Bool { vm != nil }
    
    init(document: VMDocument) {
        self.document = document
        state = document.config?.installed == true ? .installed : .needsInstall
    }
    
    /// §8a.3 escape hatch: only after an aborted install with SB on.
    var showsSecureBootEscape: Bool {
        state == .needsInstall && document?.config?.secureBoot == true
    }
    
    // MARK: User actions
    
    func install(iso: URL) {
        guard state == .needsInstall else { return }
        isoURL = iso
        didAutoRetry = false
        Task { await boot(.installing) }
    }
    
    func run() {
        guard state == .installed else { return }
        didAutoRetry = false
        Task { await boot(.running) }
    }
    
    func turnOffSecureBoot() {
        do {
            try document?.updateConfig { $0.secureBoot = false }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
    
    // MARK: Boot
    
    private func boot(_ phase: State) async {
        guard !isClosed, let document, let layout = document.layout,
              let config = document.config
                else { return }
        
        do {
            lock = try PackageLock(root: layout.root)
            try SecureBoot.sync(enabled: config.secureBoot, layout: layout)
            let configuration = try VMConfigurationBuilder.make(
                layout: layout, isoURL: phase == .installing ? isoURL : nil)
            
            let vm = VZVirtualMachine(configuration: configuration)
            vm.delegate = self
            self.vm = vm
            state = phase
            bootStart = .now
            try await vm.start()
        } catch {
            tearDown()
            state = restingState
            alertMessage = error.localizedDescription
        }
    }
    
    private var restingState: State {
        document?.config?.installed == true ? .installed : .needsInstall
    }
    
    private func tearDown() {
        vm = nil
        lock = nil
        bootStart = nil
    }
    
    // MARK: Stop handling (§8, §8a)
    
    fileprivate func handleStop(error: (any Error)?) {
        // Closing/quitting: no SB retry, no "installed" marking.
        if isClosed {
            tearDown()
            state = restingState
            resumeStopWaiter(stopped: true)
            return
        }
        
        let phase = state
        let elapsed = bootStart.map { ContinuousClock.now - $0 }
        tearDown()
        
        if let elapsed, elapsed < Self.earlyStopWindow,
           document?.config?.secureBoot == true, !didAutoRetry
        {
            do {
                try document?.updateConfig { $0.secureBoot = false }
                didAutoRetry = true
                show(notice: "Secure Boot unsupported by guest — retrying without it.")
                Task { await boot(phase) }
                return
            } catch {
                alertMessage = error.localizedDescription
                state = restingState
                return
            }
        }
        
        if let error {
            alertMessage = error.localizedDescription
            state = restingState
            return
        }
        
        if phase == .installing {
            do {
                try document?.updateConfig { $0.installed = true }
                isoURL = nil
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        state = restingState
    }
    
    private func show(notice text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(6))
            if notice == text { notice = nil }
        }
    }
    
    // MARK: Shutdown (§10.1)
    
    /// Graceful stop, then force after timeout. The controller is closed
    /// afterwards: no further boots or auto-retries.
    func shutdown() async {
        isClosed = true
        guard let vm else { return }
        defer { shutdownPhase = nil }
        
        if vm.canRequestStop {
            shutdownPhase = .requesting
            do {
                try vm.requestStop()
                if await waitForStop(timeout: Self.shutdownTimeout) { return }
            } catch {
                // Guest refused the request; fall through to force stop.
            }
        }
        
        guard self.vm === vm else { return }  // Stopped while waiting.
        shutdownPhase = .forcing
        do {
            try await vm.stop()
        } catch {
            alertMessage = error.localizedDescription
        }
        tearDown()
        state = restingState
    }
    
    private func waitForStop(timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            stopWaiter = continuation
            stopTimeoutTask = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                resumeStopWaiter(stopped: false)
            }
        }
    }
    
    private func resumeStopWaiter(stopped: Bool) {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        stopWaiter?.resume(returning: stopped)
        stopWaiter = nil
    }
}

extension VMController: VZVirtualMachineDelegate {
    // The VM is created on the main queue, so callbacks arrive there.
    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        MainActor.assumeIsolated { handleStop(error: nil) }
    }
    
    nonisolated func virtualMachine(
        _ virtualMachine: VZVirtualMachine, didStopWithError error: any Error
    ) {
        MainActor.assumeIsolated { handleStop(error: error) }
    }
}
