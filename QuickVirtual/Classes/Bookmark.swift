//
//  Bookmark.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Foundation
import os

nonisolated enum LastPackageBookmark {
    private static let key = "lastPackageBookmark"
    private static let log = Logger(
        subsystem: "com.example.quickvirtual", category: "bookmark")
    
    static func save(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            log.error("Bookmark save failed: \(error.localizedDescription)")
        }
    }
    
    /// Returns nil if unresolvable (deleted, volume not mounted). A resolved
    /// but "stale" bookmark (package moved) is still returned; it is
    /// refreshed when the document opens.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &isStale)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            log.info("Bookmark unresolvable: \(error.localizedDescription)")
            return nil
        }
    }
}
