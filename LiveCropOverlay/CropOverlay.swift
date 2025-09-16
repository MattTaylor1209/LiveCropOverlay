import SwiftUI

/// Interactive, drag-to-crop overlay drawn on top of a displayed image.
/// Keeps crop in *source pixels* via `cropInSourcePx`.
struct CropOverlay: View {
    // Geometry of the displayed (scaled) image, in the parent view's space.
    let displayedImageSize: CGSize
    let displayedImageOrigin: CGPoint
    // Original source image size in pixels
    let sourceImageSize: CGSize

    /// Crop rect in source pixels. `nil` = full image / no crop.
    @Binding var cropInSourcePx: CGRect?
    /// When true, shows handles and allows interaction.
    @Binding var isEditing: Bool

    // Working rect in *display* coordinates while editing.
    @State private var displayRect: CGRect? = nil

    // UI tuning
    private let handleSide: CGFloat = 18
    private let minSize: CGFloat = 12

    var body: some View {
        ZStack {
            // Darken outside area when we have a rect
            if let r = currentDisplayRect {
                let imgRect = imageBounds
                Path { p in
                    p.addRect(imgRect)
                    p.addRect(r)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            }

            // Selection border
            if let r = currentDisplayRect {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6,4]))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)
            }

            if isEditing {
                if let r = displayRect {
                    // Move gesture (drag inside selection)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .contentShape(Rectangle())
                        .gesture(moveGesture())

                    // 8 resize handles
                    ForEach(Handle.allCases, id: \.self) { handle in
                        let p = handlePoint(for: handle, rect: r)
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.white, lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.95)))
                            .frame(width: handleSide, height: handleSide)
                            .position(p)
                            .gesture(resizeGesture(for: handle))
                    }
                } else {
                    // ⬅️ IMPORTANT: Full-size transparent catcher so drags always register
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(createGesture())
                }
            }
        }
        .onAppear { syncDisplayFromSource() }
        .onChange(of: cropInSourcePx) { _, _ in syncDisplayFromSource() }
        .onChange(of: isEditing) { _, editing in
            if editing {
                // entering edit: sync display rect from current crop
                displayRect = sourceToDisplay(cropInSourcePx)
            } else {
                // leaving edit: commit and stop drawing the box
                commitToSource()
                displayRect = nil
            }
        }
    }

    // MARK: - Gestures

    private func createGesture() -> some Gesture {
        // Start immediately (click or drag)
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = clampPoint(value.startLocation)
                let cur   = clampPoint(value.location)
                displayRect = normalizedRect(from: start, to: cur)
            }
            .onEnded { value in
                // If user only clicked, create a sensible starter box
                let start = clampPoint(value.startLocation)
                var r = displayRect ?? CGRect(origin: start, size: .zero)
                let tiny = r.width < 8 || r.height < 8
                if tiny {
                    let defaultW = max(minSize * 8, displayedImageSize.width  * 0.25)
                    let defaultH = max(minSize * 6, displayedImageSize.height * 0.20)
                    r = CGRect(
                        x: min(max(start.x, imageBounds.minX), imageBounds.maxX - defaultW),
                        y: min(max(start.y, imageBounds.minY), imageBounds.maxY - defaultH),
                        width: defaultW,
                        height: defaultH
                    )
                }
                r = clampRect(r)
                displayRect = r
                commitToSource()
            }
    }

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard var r = displayRect else { return }
                r.origin.x += value.translation.width
                r.origin.y += value.translation.height
                r = clampRect(r)
                displayRect = r
            }
            .onEnded { _ in commitToSource() }
    }

    private func resizeGesture(for handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard var r = displayRect else { return }
                let p = clampPoint(value.location)

                switch handle {
                case .nw:
                    let maxX = r.maxX, maxY = r.maxY
                    r.origin.x = min(p.x, maxX - minSize)
                    r.origin.y = min(p.y, maxY - minSize)
                    r.size.width  = maxX - r.origin.x
                    r.size.height = maxY - r.origin.y
                case .ne:
                    let minX = r.minX, maxY = r.maxY
                    r.size.width  = max(minSize, p.x - minX)
                    r.origin.y = min(p.y, maxY - minSize)
                    r.size.height = maxY - r.origin.y
                case .sw:
                    let maxX = r.maxX, minY = r.minY
                    r.origin.x = min(p.x, maxX - minSize)
                    r.size.width  = maxX - r.origin.x
                    r.size.height = max(minSize, p.y - minY)
                case .se:
                    let minX = r.minX, minY = r.minY
                    r.size.width  = max(minSize, p.x - minX)
                    r.size.height = max(minSize, p.y - minY)
                case .n:
                    let maxY = r.maxY
                    r.origin.y = min(p.y, maxY - minSize)
                    r.size.height = maxY - r.origin.y
                case .s:
                    let minY = r.minY
                    r.size.height = max(minSize, p.y - minY)
                case .w:
                    let maxX = r.maxX
                    r.origin.x = min(p.x, maxX - minSize)
                    r.size.width = maxX - r.origin.x
                case .e:
                    let minX = r.minX
                    r.size.width = max(minSize, p.x - minX)
                }

                r = clampRect(r)
                displayRect = r
            }
            .onEnded { _ in commitToSource() }
    }

    // MARK: - Helpers

    private enum Handle: CaseIterable { case nw, n, ne, w, e, sw, s, se }

    private var imageBounds: CGRect {
        CGRect(origin: displayedImageOrigin, size: displayedImageSize)
    }

    private var currentDisplayRect: CGRect? {
        // Only show the rectangle while editing crop
        guard isEditing else { return nil }
        return displayRect
    }

    private func handlePoint(for h: Handle, rect r: CGRect) -> CGPoint {
        switch h {
        case .nw: return CGPoint(x: r.minX, y: r.minY)
        case .n:  return CGPoint(x: r.midX, y: r.minY)
        case .ne: return CGPoint(x: r.maxX, y: r.minY)
        case .w:  return CGPoint(x: r.minX, y: r.midY)
        case .e:  return CGPoint(x: r.maxX, y: r.midY)
        case .sw: return CGPoint(x: r.minX, y: r.maxY)
        case .s:  return CGPoint(x: r.midX, y: r.maxY)
        case .se: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func clampPoint(_ p: CGPoint) -> CGPoint {
        let r = imageBounds
        return CGPoint(x: min(max(p.x, r.minX), r.maxX),
                       y: min(max(p.y, r.minY), r.maxY))
    }

    private func clampRect(_ rect: CGRect) -> CGRect {
        var r = rect
        let b = imageBounds
        if r.minX < b.minX { r.origin.x = b.minX }
        if r.minY < b.minY { r.origin.y = b.minY }
        if r.maxX > b.maxX { r.size.width  = b.maxX - r.origin.x }
        if r.maxY > b.maxY { r.size.height = b.maxY - r.origin.y }
        r.size.width  = max(r.size.width,  minSize)
        r.size.height = max(r.size.height, minSize)
        return r
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(a.x - b.x),
               height: abs(a.y - b.y))
    }

    // Mapping: source <-> display (Y flipped)
    private var scale: CGFloat {
        min(displayedImageSize.width / sourceImageSize.width,
            displayedImageSize.height / sourceImageSize.height)
    }

    private func sourceToDisplay(_ src: CGRect?) -> CGRect? {
        guard let src = src else { return nil }
        let dispX = displayedImageOrigin.x + src.origin.x * scale
        let dispY = displayedImageOrigin.y
            + (sourceImageSize.height - (src.origin.y + src.height)) * scale
        return CGRect(x: dispX, y: dispY,
                      width: src.width * scale, height: src.height * scale)
    }

    private func displayToSource(_ disp: CGRect) -> CGRect {
        let x = max(0, (disp.origin.x - displayedImageOrigin.x) / scale)
        let yTopFromDisplayTop = (disp.origin.y - displayedImageOrigin.y) / scale
        let heightPx = disp.height / scale
        let y = max(0, sourceImageSize.height - yTopFromDisplayTop - heightPx)
        let w = min(sourceImageSize.width  - x, disp.width  / scale)
        let h = min(sourceImageSize.height - y, heightPx)
        return CGRect(x: floor(x), y: floor(y), width: floor(w), height: floor(h))
    }

    private func syncDisplayFromSource() {
        displayRect = sourceToDisplay(cropInSourcePx)
    }

    private func commitToSource() {
        if let r = displayRect {
            cropInSourcePx = displayToSource(r)
        } else {
            cropInSourcePx = nil
        }
    }
}
