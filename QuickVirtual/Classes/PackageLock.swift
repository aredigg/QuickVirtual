//
//  PackageLock.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation

/// Exclusive advisory lock on the package directory for the VM's lifetime.
nonisolated final class PackageLock {
    enum Error: Swift.Error, LocalizedError {
        case inUse
        case posix(Int32)
        
        var errorDescription: String? {
            switch self {
            case .inUse: "This VM is already running in another process."
            case .posix(let code): String(cString: strerror(code))
            }
        }
    }
    
    private let fd: Int32
    
    init(root: URL) throws {
        let fd = open(root.path, O_RDONLY)
        guard fd >= 0 else { throw Error.posix(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            throw code == EWOULDBLOCK ? Error.inUse : Error.posix(code)
        }
        self.fd = fd
    }
    
    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
