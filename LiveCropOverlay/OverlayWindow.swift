import AppKit
import SwiftUI

/// A borderless, always-on-top floating window for the live preview.
/// This version purposely stays NON-KEY (won’t take focus).
final class OverlayWindow: NSPanel {
    init() {
        // Non-activating panel so it never becomes key/main.
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        super.init(contentRect: NSRect(x: 240, y: 240, width: 480, height: 270),
                   styleMask: style,
                   backing: .buffered,
                   defer: false)

        isReleasedWhenClosed = false
        level = .floating                         // stay above normal windows
        collectionBehavior = [.canJoinAllSpaces,  // show on all Spaces
                              .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    func setClickThrough(_ enabled: Bool) { ignoresMouseEvents = enabled }
    func setOpacity(_ alpha: CGFloat)     { alphaValue = max(0.1, min(alpha, 1.0)) }
}
