import AppKit
import SwiftUI

/// A borderless, always-on-top window that can be click-through and shown on all spaces.
final class OverlayWindow: NSPanel {
    init() {
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        super.init(contentRect: NSRect(x: 200, y: 200, width: 480, height: 270),
                   styleMask: style,
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }

    func setClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = enabled
    }

    func setOpacity(_ alpha: CGFloat) {
        alphaValue = max(0.1, min(1.0, alpha))
    }
}

/// SwiftUI -> AppKit bridge for the overlay.
struct OverlayHost: NSViewRepresentable {
    var view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
