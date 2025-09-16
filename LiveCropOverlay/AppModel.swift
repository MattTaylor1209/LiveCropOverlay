import Foundation
import ScreenCaptureKit
import Combine   // ← add this

final class AppModel: ObservableObject {
    @Published var windows: [SCWindow] = []
    @Published var selectedWindow: SCWindow? = nil

    func refreshShareableContent() async {
        do {
            let content = try await SCShareableContent.current
            // Filter out windows that aren't shareable or are tiny/hidden.
            let visible = content.windows.filter { $0.isOnScreen && $0.frame.width > 50 && $0.frame.height > 50 }
            DispatchQueue.main.async {
                self.windows = visible.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            }
        } catch {
            print("Failed to fetch shareable content:", error)
        }
    }
}
