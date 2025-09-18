import AppKit
import SwiftUI

final class OverlayWindow: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 240, y: 240, width: 480, height: 270),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false

        // Behave like a normal window by default (not always-on-top)
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    func setClickThrough(_ enabled: Bool) { ignoresMouseEvents = enabled }
    func setOpacity(_ alpha: CGFloat)     { alphaValue = max(0.1, min(alpha, 1.0)) }

    /// Toggle "always on top" behavior.
    func setPinnedOnTop(_ on: Bool) {
        level = on ? .floating : .normal
        orderFront(nil) // bring forward, but respect normal z-order rules
    }
}
