import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var capture = CaptureManager()

    // Overlay window + UI state
    @State private var overlayWindow: OverlayWindow? = nil
    @State private var overlayOpacity: Double = 0.95
    @State private var overlayScale: Double = 1.0
    @State private var clickThrough = false
    @State private var showGuides = false
    @State private var isEditingCrop = false

    // Start/Stop state
    @State private var isOverlayRunning = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Refresh Windows") { Task { await model.refreshShareableContent() } }
                Spacer()
            }

            // Window picker
            Picker("Select a window:", selection: $model.selectedWindow) {
                Text("— none —").tag(SCWindow?.none)
                ForEach(model.windows, id: \.self) { w in
                    let app = w.owningApplication?.applicationName ?? "App"
                    Text("\(app) — \(w.title ?? "Untitled")").tag(SCWindow?.some(w))
                }
            }
            .onChange(of: model.selectedWindow) { _, newValue in
                // If the overlay is running and you pick a different window, restart onto it.
                guard isOverlayRunning, let w = newValue else { return }
                Task { await restartOverlay(on: w) }
            }

            GroupBox("Overlay") {
                HStack(spacing: 16) {
                    Toggle("Click-through", isOn: $clickThrough)
                        .onChange(of: clickThrough) { _, on in
                            if !isEditingCrop { overlayWindow?.setClickThrough(on) }
                        }

                    Toggle("Show guides", isOn: $showGuides)

                    Toggle("Edit crop", isOn: $isEditingCrop)

                    HStack(spacing: 8) {
                        Text("Opacity")
                        Slider(value: $overlayOpacity, in: 0.1...1.0)
                            .frame(maxWidth: 140)
                            .onChange(of: overlayOpacity) { _, v in overlayWindow?.setOpacity(v) }
                    }

                    HStack(spacing: 8) {
                        Text("Scale")
                        Slider(value: $overlayScale, in: 0.25...2.5)
                            .frame(maxWidth: 140)
                            .onChange(of: overlayScale) { _, _ in applyOverlaySize() }
                    }

                    Spacer()

                    // Start / Stop + Focus
                    if isOverlayRunning {
                        Button(role: .destructive, action: { Task { await stopOverlay() } }) {
                            Text("Stop Overlay")
                        }
                        Button("Focus") { overlayWindow?.orderFrontRegardless() }
                            .disabled(overlayWindow == nil)
                    } else {
                        Button("Start Overlay") { Task { await startOverlay() } }
                            .disabled(model.selectedWindow == nil)
                    }
                }
            }

            // Inline sanity-check preview (live feed)
            if let img = capture.latestImage {
                Image(decorative: img, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 360, height: 200)
                    .border(.gray)
                    .overlay(Text("Inline live preview").font(.caption).padding(4), alignment: .topLeading)
            } else {
                Text("Inline preview: no frame yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text("Pick a window → Start Overlay. Toggle ‘Edit crop’ to drag a crop on the floating window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .task { await model.refreshShareableContent() }
        .onDisappear { Task { await stopOverlay() } }

        // Clear the temp tint and keep size sane when the first frame arrives.
        .onChange(of: capture.latestImage) { _, img in
            if img != nil {
                overlayWindow?.backgroundColor = .clear
                applyOverlaySize()
            }
        }

        // While editing: make the panel key, accept mouse; otherwise restore your prefs.
        .onChange(of: isEditingCrop) { _, editing in
            if editing {
                overlayWindow?.orderFrontRegardless()
                overlayWindow?.makeKeyAndOrderFront(nil)
                overlayWindow?.isMovableByWindowBackground = false
                overlayWindow?.setClickThrough(false)
            } else {
                overlayWindow?.orderFrontRegardless()
                overlayWindow?.isMovableByWindowBackground = true
                overlayWindow?.setClickThrough(clickThrough)
            }
        }
    }

    // MARK: - Start / Stop / Restart

    private func startOverlay() async {
        guard let w = model.selectedWindow else { return }
        await capture.start(window: w, scale: 1.0)
        ensureOverlay()
        isOverlayRunning = true
    }

    private func stopOverlay() async {
        // Exit edit mode so gestures/flags reset
        isEditingCrop = false

        await capture.stop()
        if let win = overlayWindow {
            win.orderOut(nil)
            win.close()
        }
        overlayWindow = nil
        isOverlayRunning = false
    }

    private func restartOverlay(on window: SCWindow) async {
        await capture.start(window: window, scale: 1.0)
        ensureOverlay()
        isOverlayRunning = true
    }

    // MARK: - Overlay management

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = OverlayWindow()

            // The overlay view observes `capture` directly.
            let hosting = NSHostingView(rootView:
                OverlayView(
                    capture: capture,
                    showGuides: $showGuides,
                    isEditingCrop: $isEditingCrop,
                    cropInSourcePx: Binding(
                        get: { capture.cropRect },
                        set: { capture.cropRect = $0 }
                    )
                )
                .frame(minWidth: 240, minHeight: 160)
            )

            hosting.wantsLayer = true
            window.contentView = hosting
            window.setOpacity(overlayOpacity)
            window.setClickThrough(isEditingCrop ? false : clickThrough)

            // TEMP tint so you can see it before frames arrive
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25)
            window.isOpaque = false

            window.orderFrontRegardless()
            overlayWindow = window

            applyOverlaySize()
        } else {
            overlayWindow?.orderFrontRegardless()
        }
    }

    /// Resize the floating panel while preserving aspect.
    private func applyOverlaySize() {
        guard let window = overlayWindow else { return }
        let baseW = Double(capture.latestImage?.width  ?? 640)
        let baseH = Double(capture.latestImage?.height ?? 360)

        let w = max(240.0, min(1920.0, baseW * overlayScale))
        let h = max(160.0, min(1080.0, baseH * overlayScale))

        window.setContentSize(NSSize(width: w, height: h))
    }
}

#Preview {
    ContentView().environmentObject(AppModel())
}
