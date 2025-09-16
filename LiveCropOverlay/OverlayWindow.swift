import AppKit
import SwiftUI

/// Floating overlay window. It can become key (to receive drag gestures)
/// when we enter "Edit crop", and otherwise behaves like a normal floating panel.
final class OverlayWindow: NSPanel {

    // Allow this panel to become key so gestures work.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        // NOTE: drop `.nonactivatingPanel` so we can programmatically make it key.
        let style: NSWindow.StyleMask = [.borderless]
        super.init(contentRect: NSRect(x: 240, y: 240, width: 480, height: 270),
                   styleMask: style,
                   backing: .buffered,
                   defer: false)

        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    func setClickThrough(_ enabled: Bool) { ignoresMouseEvents = enabled }
    func setOpacity(_ alpha: CGFloat)     { alphaValue = max(0.1, min(alpha, 1.0)) }
}
