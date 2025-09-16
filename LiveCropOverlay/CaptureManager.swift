import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage
import Combine

/// Manages a ScreenCaptureKit stream for a single window, and provides a CGImage for display.
final class CaptureManager: NSObject, ObservableObject {
    @Published var latestImage: CGImage? = nil

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "capture.video.queue")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Cropping: expressed in source window coordinates.
    @Published var cropRect: CGRect? = nil

    func start(window: SCWindow, scale: CGFloat = 1.0) async {
        await stop()

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.showsCursor = false
            config.scalesToFit = true
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            print("Failed to start stream:", error)
        }
    }

    func stop() async {
        if let stream = stream {
            do {
                try await stream.stopCapture()
            } catch {
                print("Stop capture error:", error)
            }
            self.stream = nil
        }
    }

    private func imageFrom(sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        var cgImage = ciContext.createCGImage(
            CIImage(cvImageBuffer: imageBuffer),
            from: CGRect(x: 0, y: 0,
                         width: CVPixelBufferGetWidth(imageBuffer),
                         height: CVPixelBufferGetHeight(imageBuffer))
        )

        // Apply crop if requested (coordinates in source pixels)
        if let crop = cropRect, let img = cgImage {
            // Clamp to image bounds
            let clamped = CGRect(
                x: max(0, crop.origin.x),
                y: max(0, crop.origin.y),
                width: min(CGFloat(img.width) - crop.origin.x, crop.width),
                height: min(CGFloat(img.height) - crop.origin.y, crop.height)
            )
            if clamped.width > 1, clamped.height > 1,
               let cropped = img.cropping(to: clamped) {
                cgImage = cropped
            }
        }
        return cgImage
    }
}

extension CaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        if let img = imageFrom(sampleBuffer: sampleBuffer) {
            DispatchQueue.main.async { self.latestImage = img }
        }
    }
}

extension CaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error:", error)
    }
}
