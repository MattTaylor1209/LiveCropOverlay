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
    @State private var isEditingCrop = true  // start with crop editor ON

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
                    let appName = w.owningApplication?.applicationName ?? "App"
                    Text("\(appName) — \(w.title ?? "Untitled")").tag(SCWindow?.some(w))
                }
            }
            .onChange(of: model.selectedWindow) { _, newValue in
                Task {
                    if let w = newValue {
                        await capture.start(window: w, scale: 1.0)
                        ensureOverlay()   // create/show the floating window
                    }
                }
            }

            GroupBox("Overlay") {
                HStack(spacing: 16) {
                    Toggle("Click-through", isOn: $clickThrough)
                        .onChange(of: clickThrough) { _, on in
                            // Respect click-through only when NOT editing crop
                            if !isEditingCrop { overlayWindow?.setClickThrough(on) }
                        }

                    Toggle("Show guides", isOn: $showGuides)

                    Toggle("Edit crop", isOn: $isEditingCrop)

                    HStack(spacing: 8) {
                        Text("Opacity")
                        Slider(value: $overlayOpacity, in: 0.1...1.0)
                            .frame(maxWidth: 160)
                            .onChange(of: overlayOpacity) { _, v in overlayWindow?.setOpacity(v) }
                    }

                    HStack(spacing: 8) {
                        Text("Scale")
                        Slider(value: $overlayScale, in: 0.25...2.5)
                            .frame(maxWidth: 160)
                            .onChange(of: overlayScale) { _, _ in applyOverlaySize() }
                    }

                    Spacer()
                    Button("Show/Focus Overlay") { ensureOverlay() }  // bring to front (non-key unless editing)
                        .disabled(capture.latestImage == nil)
                }
            }

            // Inline sanity-check preview (should show the live feed)
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
            Text("Pick a window → Show/Focus Overlay. Toggle ‘Edit crop’, then drag on the floating window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .task { await model.refreshShareableContent() }
        .onDisappear { Task { await capture.stop() } }

        // Clear temporary tint and keep size sensible once frames arrive
        .onChange(of: capture.latestImage) { _, img in
            if img != nil {
                overlayWindow?.backgroundColor = .clear
                applyOverlaySize()
            }
        }

        // When entering crop edit mode, make the panel key so drag gestures work.
        .onChange(of: isEditingCrop) { _, editing in
            if editing {
                // Make panel key so SwiftUI gestures receive drag events
                overlayWindow?.orderFrontRegardless()
                overlayWindow?.makeKeyAndOrderFront(nil)

                // VERY IMPORTANT: don't let the window treat drags as "move window"
                overlayWindow?.isMovableByWindowBackground = false

                // Must accept mouse while editing
                overlayWindow?.setClickThrough(false)
            } else {
                overlayWindow?.orderFrontRegardless()

                // Restore your preferred behavior
                overlayWindow?.isMovableByWindowBackground = true
                overlayWindow?.setClickThrough(clickThrough)
            }
        }
    }

    // MARK: - Overlay management

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = OverlayWindow()

            // OverlayView observes `capture` directly, so it auto-updates.
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

            // TEMP tint so you can see the panel before frames arrive
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25)
            window.isOpaque = false

            // Show (we only make it key when editing crop)
            window.orderFrontRegardless()
            overlayWindow = window

            // Initial sizing
            applyOverlaySize()
        } else {
            overlayWindow?.orderFrontRegardless()
        }
    }

    /// Resize the floating panel while preserving aspect.
    private func applyOverlaySize() {
        guard let window = overlayWindow else { return }
        // Use current (cropped) frame if available; otherwise fall back to a sensible base size.
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
