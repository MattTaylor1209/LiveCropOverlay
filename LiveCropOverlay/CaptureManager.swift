import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage
import Combine
import VideoToolbox

/// Manages a ScreenCaptureKit stream for a single window and publishes CGImage frames.
final class CaptureManager: NSObject, ObservableObject {
    @Published var latestImage: CGImage? = nil
    @Published var cropRect: CGRect? = nil   // in source pixels

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "capture.video.queue")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Control

    func start(window: SCWindow, scale: CGFloat = 1.0) async {
        await stop()

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)

            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.showsCursor = false
            config.scalesToFit = true
            // Force simple pixel format we can convert easily.
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.width  = max(64, Int(window.frame.width  * scale))
            config.height = max(64, Int(window.frame.height * scale))

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            try await s.startCapture()
            self.stream = s
        } catch {
            print("Failed to start stream:", error)
        }
    }

    func stop() async {
        guard let s = stream else { return }
        do {
            try await s.stopCapture()
        } catch {
            // benign if already stopped
            print("Stop capture error:", error)
        }
        self.stream = nil
        await MainActor.run { self.latestImage = nil }
    }
}

// MARK: - Frame decoding

extension CaptureManager {
    /// Robust CVPixelBuffer -> CGImage with VT (primary) and CI (fallback).
    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        // Primary: VideoToolbox
        var cgOut: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgOut)
        if status == noErr, let img = cgOut {
            return img
        }

        // Fallback: CoreImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0,
                          width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        return ciContext.createCGImage(ciImage, from: rect)
    }

    /// Applies an in-bounds crop (cropRect is in source pixels).
    private func cropped(_ image: CGImage, with crop: CGRect?) -> CGImage {
        guard let crop, crop.width >= 1, crop.height >= 1 else { return image }
        let W = CGFloat(image.width)
        let H = CGFloat(image.height)
        let clamped = CGRect(
            x: max(0, min(crop.origin.x, W - 1)),
            y: max(0, min(crop.origin.y, H - 1)),
            width: max(1, min(crop.width,  W - crop.origin.x)),
            height:max(1, min(crop.height, H - crop.origin.y))
        ).integral
        return image.cropping(to: clamped) ?? image
    }
}

// MARK: - SCStreamOutput

extension CaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType)
    {
        guard outputType == .screen,
              let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Optional debug:
        // print("frame")

        guard let base = cgImage(from: px) else { return }
        let final = cropped(base, with: cropRect)

        Task { @MainActor in
            self.latestImage = final
        }
    }
}

// MARK: - SCStreamDelegate

extension CaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error:", error)
    }
}
