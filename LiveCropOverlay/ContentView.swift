import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var capture = CaptureManager()

    // Overlay window + UI state
    @State private var overlayWindow: OverlayWindow? = nil
    @State private var overlayOpacity: Double = 0.95
    @State private var clickThrough = false
    @State private var showGuides = false
    @State private var isEditingCrop = true  // start with crop editor on

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
                        ensureOverlay()   // create/show the floating non-key window
                    }
                }
            }

            GroupBox("Overlay") {
                HStack(spacing: 16) {
                    Toggle("Click-through", isOn: $clickThrough)
                        .onChange(of: clickThrough) { _, on in overlayWindow?.setClickThrough(on) }

                    Toggle("Show guides", isOn: $showGuides)
                    Toggle("Edit crop", isOn: $isEditingCrop)

                    HStack(spacing: 8) {
                        Text("Opacity")
                        Slider(value: $overlayOpacity, in: 0.1...1.0)
                            .frame(maxWidth: 200)
                            .onChange(of: overlayOpacity) { _, v in overlayWindow?.setOpacity(v) }
                    }

                    Spacer()
                    Button("Show/Focus Overlay") { ensureOverlay() } // non-key: bring to front only
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
        // Clear the temporary tint once the first frame arrives
        .onChange(of: capture.latestImage) { _, img in
            if img != nil { overlayWindow?.backgroundColor = .clear }
        }
    }

    // MARK: - Overlay management (non-key)

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = OverlayWindow()

            // IMPORTANT: OverlayView observes `capture` directly.
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
            window.setClickThrough(clickThrough)

            // TEMP tint so you can see the panel before frames arrive
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25)
            window.isOpaque = false

            // Non-key panel: do NOT call makeKey; just bring to front
            window.orderFrontRegardless()

            overlayWindow = window
        } else {
            overlayWindow?.orderFrontRegardless()
        }
    }
}

#Preview {
    ContentView().environmentObject(AppModel())
}
