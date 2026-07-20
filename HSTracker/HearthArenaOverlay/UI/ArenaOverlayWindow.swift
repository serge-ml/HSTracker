//
//  ArenaOverlayWindow.swift
//  HSTracker
//

import AppKit

final class ArenaOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}
