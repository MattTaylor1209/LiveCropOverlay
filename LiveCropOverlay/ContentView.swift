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
    @State private var pinOnTop = true

    // Edit/apply flow
    @State private var isEditingCrop = false
    @State private var draftCrop: CGRect? = nil      // ← crop being edited (not applied yet)

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
                guard isOverlayRunning, let w = newValue else { return }
                Task { await restartOverlay(on: w) }
            }

            GroupBox("Overlay") {
                HStack(spacing: 12) {
                    Toggle("Click-through", isOn: $clickThrough)
                        .onChange(of: clickThrough) { _, on in
                            if !isEditingCrop { overlayWindow?.setClickThrough(on) }
                        }
                    
                    // Guides toggle
                    Toggle("Show guides", isOn: $showGuides)

                    // Edit toggle
                    Toggle("Edit crop", isOn: $isEditingCrop)
                    
                    // Pin on top of other windows
                    Toggle("Pin on top", isOn: $pinOnTop)
                        .onChange(of: pinOnTop) { _, on in overlayWindow?.setPinnedOnTop(on) }

                    // Confirm / Cancel appear only while editing
                    if isEditingCrop {
                        Button("Confirm Crop") { applyDraftCrop() }
                            .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            cancelDraftCrop()
                        }
                    } else {
                        // Reset is available outside edit mode
                        Button("Reset Crop") { resetCrop() }
                            .disabled(capture.cropRect == nil)
                    }

                    // Opacity & Scale
                    HStack(spacing: 6) {
                        Text("Opacity")
                        Slider(value: $overlayOpacity, in: 0.1...1.0)
                            .frame(maxWidth: 140)
                            .onChange(of: overlayOpacity) { _, v in overlayWindow?.setOpacity(v) }
                    }
                    HStack(spacing: 6) {
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
            Text("Start Overlay → toggle ‘Edit crop’ to draw. Use Confirm/Cancel to apply or discard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .task { await model.refreshShareableContent() }
        .onDisappear { Task { await stopOverlay() } }

        // First frame: clear temp tint & size panel nicely
        .onChange(of: capture.latestImage) { _, img in
            if img != nil {
                overlayWindow?.backgroundColor = .clear
                applyOverlaySize()
            }
        }

        // Enter/exit edit mode behavior
        .onChange(of: isEditingCrop) { _, editing in
            if editing {
                // Start from current applied crop
                draftCrop = capture.cropRect

                overlayWindow?.orderFrontRegardless()
                overlayWindow?.makeKeyAndOrderFront(nil)        // receive drags
                overlayWindow?.isMovableByWindowBackground = false
                overlayWindow?.setClickThrough(false)            // must accept mouse while editing
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
        resetCrop()                               // fresh start
        await capture.start(window: w, scale: 1.0)
        ensureOverlay()
        isOverlayRunning = true
    }

    private func stopOverlay() async {
        isEditingCrop = false
        resetCrop()                               // next start is full window
        await capture.stop()
        if let win = overlayWindow {
            win.orderOut(nil)
            win.close()
        }
        overlayWindow = nil
        isOverlayRunning = false
    }

    private func restartOverlay(on window: SCWindow) async {
        resetCrop()
        await capture.start(window: window, scale: 1.0)
        ensureOverlay()
        isOverlayRunning = true
    }

    // MARK: - Overlay management

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = OverlayWindow()
            
            // The overlay view observes `capture` directly, but binds to DRAFT crop.
            let hosting = NSHostingView(rootView:
                OverlayView(
                    capture: capture,
                    showGuides: $showGuides,
                    isEditingCrop: $isEditingCrop,
                    cropInSourcePx: Binding(
                        get: { draftCrop },          // ← edit into the draft
                        set: { draftCrop = $0 }
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
            overlayWindow?.setPinnedOnTop(pinOnTop)

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

    // MARK: - Actions

    /// Apply the draft crop to the live stream and exit edit mode.
    private func applyDraftCrop() {
        capture.cropRect = draftCrop            // ← live now
        isEditingCrop = false
    }

    /// Discard draft and exit edit mode (live crop unchanged).
    private func cancelDraftCrop() {
        draftCrop = nil
        isEditingCrop = false
    }

    /// Return to full-window view (both live & draft).
    private func resetCrop() {
        draftCrop = nil
        capture.cropRect = nil
    }
}

#Preview {
    ContentView().environmentObject(AppModel())
}
