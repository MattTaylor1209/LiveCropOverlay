import SwiftUI

/// Displays a CGImage, allows optional visual crop overlay (drag handles).
struct OverlayView: View {
    let image: CGImage?
    @Binding var showGuides: Bool

    var body: some View {
        GeometryReader { geo in
            if let image = image {
                // Fit image to available space, preserving aspect.
                let imgSize = CGSize(width: image.width, height: image.height)
                let scale = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
                let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)

                ZStack {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: drawSize.width, height: drawSize.height)
                        .position(x: geo.size.width/2, y: geo.size.height/2)

                    if showGuides {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6,4]))
                            .padding(8)
                    }
                }
                .background(Color.clear)
            } else {
                Color.clear
            }
        }
    }
}
