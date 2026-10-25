//
//  WindowState.swift
//  QuickVirtual
//
//  Created by Are Digranes on 25/10/2026.
//

import Observation

/// Per-window UI state shared between the window delegate and SwiftUI.
@Observable
final class WindowState {
    var isFullScreen = false
}
