# LiveCropOverlay

A small macOS utility that creates a **live, always-on-top overlay** of any application window, with cropping and transparency controls. Great for coding, presenting, monitoring logs, or keeping an eye on a process while you work elsewhere.

---

##  Features

- Select any running window and mirror it in a floating overlay.
- Overlay stays **always on top** (optional **click-through**).
- **Edit crop** with drag handles (non-destructive, confirm/cancel flow).
- **Reset crop** to return to the full window view at any time.
- Adjust **opacity** and **scale** (preserves aspect ratio).
- **Start / Stop** the overlay to quickly switch between windows.
- Inline preview inside the app for quick sanity checks.

---

##  Getting Started

### Requirements
- macOS 13 Ventura or newer  
  *(ScreenCaptureKit is available from macOS 12.3+, but newer versions work best.)*
- Xcode 15+

### Build & Run
```bash
git clone https://github.com/yourusername/LiveCropOverlay.git
cd LiveCropOverlay
open LiveCropOverlay.xcodeproj
# Build & run in Xcode with ⌘R
```

### Permissions

On first capture, macOS will request Screen Recording permission.
Grant via: System Settings → Privacy & Security → Screen Recording → enable LiveCropOverlay (or Xcode while running from the IDE).

## Usage

1.	Launch the app.
2.	Click Refresh Windows and pick a window from the dropdown.
3.	Click Start Overlay to open the floating PiP.
4.	(Optional) Edit crop → draw/resize the box → Confirm or Cancel.
5.	Reset Crop at any time to show the full window.
6.	Use Opacity and Scale to adjust appearance.
7.	Toggle Click-through to let clicks pass to apps underneath.
8.	Stop Overlay to close and reset; select a different window and start again.
