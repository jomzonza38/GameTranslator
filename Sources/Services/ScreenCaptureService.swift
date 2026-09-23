import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreMedia

/// Delegate to receive captured frames
protocol ScreenCaptureDelegate: AnyObject {
    func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage, contentRect: CGRect)
    func screenCaptureService(_ service: ScreenCaptureService, didEncounterError error: Error)
}

/// Service that captures frames from a selected window using ScreenCaptureKit
final class ScreenCaptureService: NSObject, @unchecked Sendable {
    weak var delegate: ScreenCaptureDelegate?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var selectedWindow: SCWindow?
    private var isCapturing = false
    private let captureQueue = DispatchQueue(label: "com.worawalan.GameTranslator.capture", qos: .userInitiated)

    /// Get list of available windows for capture
    /// Bundle identifiers of system UI that owns full-screen or decorative windows.
    /// These show up in SCShareableContent but are never something the user wants to
    /// translate, and picking one (the Dock's wallpaper window in particular) produces
    /// a capture that never delivers a second frame.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent"
    ]

    /// Window titles used by system chrome that has no owning application.
    private static let excludedTitles: Set<String> = [
        "underbelly",
        "Wallpaper-",
        "Display 1 Backstop",
        "Backstop"
    ]

    static func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.filter { window in
            // Filter out system UI and tiny windows
            guard let title = window.title, !title.isEmpty else { return false }
            guard window.frame.width > 100 && window.frame.height > 100 else { return false }
            // Exclude our own app
            guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            // Exclude system UI (Dock, wallpaper, Notification Center, menu bar chrome)
            if let bundleID = window.owningApplication?.bundleIdentifier,
               excludedBundleIDs.contains(bundleID) {
                return false
            }
            // Windows with no owning app are system chrome (backstop, wallpaper, menu bar)
            guard window.owningApplication != nil else { return false }
            if excludedTitles.contains(title) || title.hasPrefix("Wallpaper") || title.hasSuffix("Backstop") {
                return false
            }
            return true
        }
    }

    /// Start capturing the selected window
    func startCapture(window: SCWindow, frameRate: Double = 5.0) async throws {
        guard !isCapturing else { return }

        selectedWindow = window

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2  // Retina
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = StreamOutput { [weak self] image in
            guard let self = self, let window = self.selectedWindow else { return }
            self.delegate?.screenCaptureService(self, didCaptureFrame: image, contentRect: window.frame)
        }
        self.streamOutput = output

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
        self.isCapturing = true
    }

    /// Stop capturing
    func stopCapture() async {
        guard isCapturing else { return }

        try? await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        selectedWindow = nil
        isCapturing = false
    }

    /// Update capture frame rate
    func updateFrameRate(_ frameRate: Double) async throws {
        guard let stream = stream, let window = selectedWindow else { return }

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        try await stream.updateConfiguration(config)
    }

    /// Get the current game window frame
    var currentWindowFrame: CGRect? {
        guard let windowID = selectedWindow?.windowID else { return nil }

        let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        guard let windowInfo = windowList?.first,
              let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }

        return CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
    }
}

// MARK: - Stream Output Handler

private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: (CGImage) -> Void
    private var lastFrameTime: CFAbsoluteTime = 0

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Skip frames that arrive too close together
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime > 0.05 else { return } // Min 50ms between frames
        lastFrameTime = now

        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        onFrame(cgImage)
    }
}
