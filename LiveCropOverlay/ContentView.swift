import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var capture = CaptureManager()

    // Overlay window
    @State private var overlayWindow: OverlayWindow? = nil
    @State private var overlayOpacity: Double = 0.95
    @State private var clickThrough = false
    @State private var showGuides = false

    // Crop editor state (in captured-image pixel coords)
    @State private var cropEnabled = false
    @State private var cropX: CGFloat = 0
    @State private var cropY: CGFloat = 0
    @State private var cropW: CGFloat = 800
    @State private var cropH: CGFloat = 300

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Refresh Windows") { Task { await model.refreshShareableContent() } }
                Spacer()
            }

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
                        ensureOverlay()
                    }
                }
            }

            GroupBox("Overlay") {
                HStack {
                    Toggle("Click-through", isOn: $clickThrough)
                        .onChange(of: clickThrough) { _, on in
                            overlayWindow?.setClickThrough(on)
                        }
                    Toggle("Show guides", isOn: $showGuides)
                    Slider(value: $overlayOpacity, in: 0.1...1.0) {
                        Text("Opacity")
                    } minimumValueLabel: { Text("10%") } maximumValueLabel: { Text("100%") }
                    .frame(maxWidth: 240)
                    .onChange(of: overlayOpacity) { _, val in
                        overlayWindow?.setOpacity(val)
                    }

                    Spacer()
                    Button("Show/Focus Overlay") { ensureOverlay(focus: true) }.disabled(capture.latestImage == nil)
                }
            }

            GroupBox("Crop (pixels in source)") {
                HStack(spacing: 12) {
                    Toggle("Enable crop", isOn: $cropEnabled)
                        .onChange(of: cropEnabled) { _, on in
                            capture.cropRect = on ? CGRect(x: cropX, y: cropY, width: cropW, height: cropH) : nil
                        }
                    numberField("X", value: $cropX)
                    numberField("Y", value: $cropY)
                    numberField("W", value: $cropW)
                    numberField("H", value: $cropH)
                    Button("Apply") {
                        capture.cropRect = cropEnabled ? CGRect(x: cropX, y: cropY, width: cropW, height: cropH) : nil
                    }
                }
            }

            Spacer()
            Text("Tip: place this overlay on a second Space, or enable click-through to keep working under it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .task { await model.refreshShareableContent() }
        .onDisappear { Task { await capture.stop() } }
        .onChange(of: capture.latestImage) { _, _ in
            updateOverlayContent()
        }
    }

    private func ensureOverlay(focus: Bool = false) {
        if overlayWindow == nil {
            let window = OverlayWindow()
            let hosting = NSHostingView(rootView:
                OverlayView(image: capture.latestImage, showGuides: $showGuides)
                    .frame(minWidth: 240, minHeight: 160)
            )
            hosting.wantsLayer = true
            window.contentView = hosting
            window.setOpacity(overlayOpacity)
            window.setClickThrough(clickThrough)
            window.makeKeyAndOrderFront(nil)
            overlayWindow = window
        } else {
            overlayWindow?.orderFrontRegardless()
        }
        if focus {
            overlayWindow?.makeKey()
        }
        updateOverlayContent()
    }

    private func updateOverlayContent() {
        guard let window = overlayWindow,
              let hosting = window.contentView as? NSHostingView<OverlayView> else { return }
        hosting.rootView = OverlayView(image: capture.latestImage, showGuides: $showGuides)
    }

    private func numberField(_ label: String, value: Binding<CGFloat>) -> some View {
        HStack(spacing: 6) {
            Text(label).frame(width: 14, alignment: .trailing)
            TextField("", value: value, formatter: NumberFormatter.decimalNoGrouping)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension NumberFormatter {
    static var decimalNoGrouping: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = false
        nf.maximumFractionDigits = 0
        return nf
    }()
}
