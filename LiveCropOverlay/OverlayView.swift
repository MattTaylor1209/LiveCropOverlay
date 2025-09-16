import SwiftUI

struct OverlayView: View {
    @ObservedObject var capture: CaptureManager   // ← observe the manager
    @Binding var showGuides: Bool
    @Binding var isEditingCrop: Bool
    @Binding var cropInSourcePx: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = capture.latestImage {
                    let srcSize = CGSize(width: image.width, height: image.height)
                    let scale = min(geo.size.width/srcSize.width, geo.size.height/srcSize.height)
                    let drawSize = CGSize(width: srcSize.width*scale, height: srcSize.height*scale)
                    let origin = CGPoint(x: (geo.size.width - drawSize.width)/2,
                                         y: (geo.size.height - drawSize.height)/2)

                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: drawSize.width, height: drawSize.height)
                        .position(x: geo.size.width/2, y: geo.size.height/2)

                    if showGuides && !isEditingCrop {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6,4]))
                            .padding(8)
                    }

                    // Uses the drag-to-crop with proper coordinate mapping
                    CropOverlay(
                        displayedImageSize: drawSize,
                        displayedImageOrigin: origin,
                        sourceImageSize: srcSize,
                        cropInSourcePx: $cropInSourcePx,
                        isEditing: $isEditingCrop
                    )
                } else {
                    ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.2))
                            Text("Waiting for frames…")
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(6)
                        }
                }
            }
            .background(Color.clear)
        }
    }
}
