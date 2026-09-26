import AVFoundation
import CoreMedia
import CoreGraphics

// MARK: - Pure selection logic (unit-tested, T-0027 AC-1)

/// A capture device as the selection logic sees it
struct CaptureDeviceCandidate: Equatable {
    let name: String
    let uniqueID: String
    /// Core Audio transport type ('bltn' built-in, 'usb ', 'virt' virtual, …)
    let transportType: Int32
}

/// One frame-rate range of a format, with the device's own exact durations
/// (UVC cards often report discrete ranges: min = max, e.g. 1001/60000 s for 59.94)
struct CaptureFrameRateRange: Equatable {
    let minFrameRate: Double
    let maxFrameRate: Double
    /// Shortest frame duration (= maxFrameRate)
    let minFrameDuration: CMTime
    /// Longest frame duration (= minFrameRate)
    let maxFrameDuration: CMTime

    /// Whether `duration` lies inside this range (exact CMTime comparison)
    func contains(_ duration: CMTime) -> Bool {
        CMTimeCompare(duration, minFrameDuration) >= 0 && CMTimeCompare(duration, maxFrameDuration) <= 0
    }
}

/// One format a capture card offers
struct CaptureFormatCandidate: Equatable {
    let width: Int
    let height: Int
    let frameRateRanges: [CaptureFrameRateRange]
    /// FourCC of the pixel data ('jpeg', '2vuy', …)
    let fourCC: String

    var maxFrameRate: Double { frameRateRanges.map(\.maxFrameRate).max() ?? 0 }
    var isCompressed: Bool { CaptureCardSelection.compressedFourCCs.contains(fourCC) }
}

enum CaptureCardSelection {
    static let builtInTransport = fourCC("bltn")
    static let virtualTransport = fourCC("virt")
    static let aggregateTransport = fourCC("grup")

    /// Formats the card has to decode/decompress (MJPEG, H.264, HEVC)
    static let compressedFourCCs: Set<String> = ["jpeg", "dmb1", "mjpa", "mjpb", "avc1", "hvc1"]

    /// The Switch outputs 60 Hz; capturing faster only adds USB load
    static let targetFrameRate: Double = 60
    /// 1/60 s, built from integers — never from a Double fps (T-0030)
    static let targetFrameDuration = CMTime(value: 1, timescale: 60)

    /// Words in a device name that say nothing about which physical device it is
    private static let genericNameWords: Set<String> = [
        "usb", "usb2.0", "usb3.0", "usb3", "usb2", "video", "audio", "capture", "hdmi", "hd", "uhd",
        "4k", "camera", "device", "input", "output", "microphone", "mic", "digital", "interface",
    ]

    /// First real external video device: virtual cameras (OBS Virtual Camera and
    /// similar) are skipped — they would show our own or OBS's output, not the game
    static func firstCaptureCard(in devices: [CaptureDeviceCandidate]) -> CaptureDeviceCandidate? {
        devices.first { !isVirtual($0) }
    }

    static func isVirtual(_ device: CaptureDeviceCandidate) -> Bool {
        if device.transportType == virtualTransport { return true }
        let name = device.name.lowercased()
        return name.contains("virtual") || name.contains("obs ")
    }

    /// The card's own audio input. Only a device whose name identifies the same
    /// hardware as the video device qualifies — never the Mac's microphone, never a
    /// virtual or aggregate device, never "some other USB mic".
    static func matchingAudioDevice(forVideoDeviceNamed videoName: String,
                                    in devices: [CaptureDeviceCandidate]) -> CaptureDeviceCandidate? {
        let videoWords = distinctiveWords(videoName)
        let videoNormalized = normalized(videoName)

        return devices.first { audio in
            guard audio.transportType != builtInTransport,
                  audio.transportType != virtualTransport,
                  audio.transportType != aggregateTransport else { return false }
            let lower = audio.name.lowercased()
            if lower.contains("macbook") || lower.contains("built-in") || lower.contains("virtual") {
                return false
            }
            if normalized(audio.name) == videoNormalized { return true }
            return !videoWords.isDisjoint(with: distinctiveWords(audio.name))
        }
    }

    /// Index of the best format: 50/60 FPS first, then the largest picture that fits
    /// 1080p (or the smallest above it if none fits), then uncompressed over MJPEG at
    /// the same size, then the frame rate closest to 60
    static func bestFormatIndex(in formats: [CaptureFormatCandidate]) -> Int? {
        func key(_ f: CaptureFormatCandidate) -> (Int, Int, Int, Int, Double) {
            let fps = min(f.maxFrameRate, targetFrameRate)
            let fast = fps >= 49 ? 0 : 1
            let fits = f.width <= 1920 && f.height <= 1080
            let pixels = f.width * f.height
            return (fast, fits ? 0 : 1, fits ? -pixels : pixels, f.isCompressed ? 1 : 0, -fps)
        }
        return formats.indices.min { key(formats[$0]) < key(formats[$1]) }
    }

    /// Frame duration to run a format at. Always a value the format supports
    /// (setting any other one makes AVFoundation raise an exception — T-0030):
    /// - exactly 1/60 s if a range contains it;
    /// - else the fastest range below 60 fps, at that range's own shortest duration
    ///   (59.94 → 1001/60000, 30, 29.97 …);
    /// - else (only faster than 60) the slowest range, at its own longest duration.
    /// nil if the format reports no ranges (the device default is kept).
    static func frameDuration(for format: CaptureFormatCandidate) -> CMTime? {
        let ranges = format.frameRateRanges
        if ranges.contains(where: { $0.contains(targetFrameDuration) }) {
            return targetFrameDuration
        }
        if let below = ranges.filter({ $0.maxFrameRate < targetFrameRate }).max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
            return below.minFrameDuration
        }
        return ranges.min(by: { $0.minFrameRate < $1.minFrameRate })?.maxFrameDuration
    }

    /// Whether `duration` is inside one of the ranges — checked again right before
    /// it is set on the device
    static func isSupported(_ duration: CMTime, by ranges: [CaptureFrameRateRange]) -> Bool {
        duration.isValid && duration.value > 0 && ranges.contains { $0.contains(duration) }
    }

    /// Frames per second of a duration, for display only (nil if invalid)
    static func frameRate(of duration: CMTime) -> Double? {
        guard duration.isValid, duration.value > 0 else { return nil }
        return Double(duration.timescale) / Double(duration.value)
    }

    /// "1920×1080 @ 60 fps · MJPEG" (or "59.94 fps") for the menu and log
    static func describe(width: Int, height: Int, fourCC: String, frameRate: Double?) -> String {
        let fps: String
        if let frameRate {
            let rounded = (frameRate * 100).rounded() / 100
            fps = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.2f", rounded)
        } else {
            fps = "?"
        }
        return "\(width)×\(height) @ \(fps) fps · \(codecName(fourCC))"
    }

    static func codecName(_ fourCC: String) -> String {
        switch fourCC {
        case "jpeg", "dmb1", "mjpa", "mjpb": return "MJPEG"
        case "2vuy": return "UYVY (ไม่บีบอัด)"
        case "yuvs": return "YUY2 (ไม่บีบอัด)"
        case "420v", "420f": return "NV12 (ไม่บีบอัด)"
        case "BGRA": return "BGRA (ไม่บีบอัด)"
        case "avc1": return "H.264"
        case "hvc1": return "HEVC"
        default: return fourCC
        }
    }

    static func fourCC(_ string: String) -> Int32 {
        Int32(bitPattern: string.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }

    static func fourCCString(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func distinctiveWords(_ name: String) -> Set<String> {
        let words = name.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == ".") }
            .map(String.init)
        return Set(words.filter { $0.count >= 3 && !genericNameWords.contains($0) && !$0.allSatisfy(\.isNumber) })
    }
}

// MARK: - Errors

enum CaptureCardError: LocalizedError {
    case noDevice
    case cameraDenied
    case cannotOpen(String)
    case notRunning
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "ไม่พบ capture card — เสียบ capture card (เช่น Kingma) เข้ากับ Mac แล้วลองใหม่"
        case .cameraDenied:
            return "ยังไม่ได้อนุญาตให้ใช้กล้อง (capture card นับเป็นกล้อง) — เปิด System Settings → Privacy & Security → Camera แล้วเปิดสิทธิ์ให้ Game Translator"
        case .cannotOpen(let detail):
            return "เปิด capture card ไม่ได้: \(detail)"
        case .notRunning:
            return "capture card ไม่ส่งภาพ — ลองถอดแล้วเสียบใหม่ หรือปิดโปรแกรมอื่นที่ใช้อยู่ (เช่น OBS)"
        case .cancelled:
            return "ยกเลิกแล้ว"
        }
    }
}

// MARK: - Service

/// What the TV Output menu shows about the running capture
struct CaptureCardInfo {
    let deviceName: String
    let deviceID: String
    let formatDescription: String
    /// Pixel size of the picture (for aspect-fit on the TV)
    let videoSize: CGSize
}

/// Reads a UVC capture card with AVFoundation (T-0027). The picture goes from the
/// session straight to an `AVCaptureVideoPreviewLayer` — no frame passes through
/// app code. Sound plays through a second, separate session with an
/// `AVCaptureAudioPreviewOutput`, so audio can never hold up video.
///
/// All session work runs on one serial queue; `startRunning()` blocks, so the main
/// thread never calls it. Every start carries a generation number; `stop(generation:)`
/// cancels every start with a lower number, whether it is queued before or after it.
final class CaptureCardService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.worawalan.GameTranslator.capturecard")

    // Only touched on `queue`
    private var videoSession: AVCaptureSession?
    private var audioSession: AVCaptureSession?
    private var stoppedGeneration = 0

    // MARK: Discovery (cheap, any thread)

    static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    }

    static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    static func candidate(_ device: AVCaptureDevice) -> CaptureDeviceCandidate {
        CaptureDeviceCandidate(name: device.localizedName, uniqueID: device.uniqueID, transportType: device.transportType)
    }

    // MARK: Video

    /// Open the device, pick its best format and start the session. Returns the
    /// running session (for the preview layer) and what to show in the menu.
    func startVideo(deviceID: String, generation: Int) async throws -> (AVCaptureSession, CaptureCardInfo) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.startVideoOnQueue(deviceID: deviceID, generation: generation) })
            }
        }
    }

    private func startVideoOnQueue(deviceID: String, generation: Int) throws -> (AVCaptureSession, CaptureCardInfo) {
        guard generation > stoppedGeneration else { throw CaptureCardError.cancelled }
        guard let device = AVCaptureDevice(uniqueID: deviceID), device.isConnected else {
            throw CaptureCardError.noDevice
        }

        let formats = device.formats.map(Self.candidate)
        GameLog.log("TV Output: \(device.localizedName) offers \(formats.count) formats: "
                    + formats.map { "\($0.width)x\($0.height)@\(Int($0.maxFrameRate))/\($0.fourCC)" }.joined(separator: ", "))

        let session = AVCaptureSession()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureCardError.cannotOpen(error.localizedDescription)
        }

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureCardError.cannotOpen("session ไม่รับอุปกรณ์นี้")
        }
        session.addInput(input)
        session.commitConfiguration()

        guard generation > stoppedGeneration else { throw CaptureCardError.cancelled }

        // Format is set after the input is added (adding it can reset the format to
        // the session preset's). The device stays locked until startRunning() has
        // returned — otherwise the session may re-apply its preset at start and
        // replace the chosen format/frame rate (T-0030, Apple's pattern on macOS).
        var intended: String?
        var locked = false
        if let index = CaptureCardSelection.bestFormatIndex(in: formats) {
            let format = formats[index]
            do {
                try device.lockForConfiguration()
                locked = true
                device.activeFormat = device.formats[index]
                // Only a duration of this format's own ranges is ever set
                if let duration = CaptureCardSelection.frameDuration(for: format),
                   CaptureCardSelection.isSupported(duration, by: Self.candidate(device.activeFormat).frameRateRanges) {
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    intended = CaptureCardSelection.describe(width: format.width, height: format.height, fourCC: format.fourCC,
                                                             frameRate: CaptureCardSelection.frameRate(of: duration))
                } else {
                    intended = CaptureCardSelection.describe(width: format.width, height: format.height, fourCC: format.fourCC,
                                                             frameRate: nil)
                    GameLog.log("TV Output: no supported frame duration for the chosen format — keeping the device's")
                }
            } catch {
                GameLog.log("TV Output: cannot set format (\(error.localizedDescription)) — using the device default")
            }
        }

        session.startRunning()
        if locked { device.unlockForConfiguration() }
        guard session.isRunning, device.isConnected else {
            session.stopRunning()
            throw CaptureCardError.notRunning
        }
        // A stop that arrived while startRunning() was blocking
        guard generation > stoppedGeneration else {
            session.stopRunning()
            throw CaptureCardError.cancelled
        }

        videoSession = session

        // Report what is really active now, not what was asked for
        let active = Self.candidate(device.activeFormat)
        let description = CaptureCardSelection.describe(
            width: active.width, height: active.height, fourCC: active.fourCC,
            frameRate: CaptureCardSelection.frameRate(of: device.activeVideoMinFrameDuration) ?? active.maxFrameRate
        )
        GameLog.log("TV Output: capture running — \(device.localizedName), active after start: \(description)")
        if let intended, intended != description {
            GameLog.log("TV Output: ⚠️ active format differs from the chosen one (\(intended))")
        }
        return (session, CaptureCardInfo(deviceName: device.localizedName, deviceID: device.uniqueID,
                                         formatDescription: description,
                                         videoSize: CGSize(width: active.width, height: active.height)))
    }

    private static func candidate(_ format: AVCaptureDevice.Format) -> CaptureFormatCandidate {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CaptureFormatCandidate(
            width: Int(dims.width),
            height: Int(dims.height),
            frameRateRanges: format.videoSupportedFrameRateRanges.map {
                CaptureFrameRateRange(minFrameRate: $0.minFrameRate, maxFrameRate: $0.maxFrameRate,
                                      minFrameDuration: $0.minFrameDuration, maxFrameDuration: $0.maxFrameDuration)
            },
            fourCC: CaptureCardSelection.fourCCString(CMFormatDescriptionGetMediaSubType(format.formatDescription))
        )
    }

    // MARK: Audio

    /// Play the card's sound to the Mac's current output. Returns false (and logs) if
    /// it cannot; the picture keeps running either way.
    func startAudio(deviceID: String, generation: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.startAudioOnQueue(deviceID: deviceID, generation: generation))
            }
        }
    }

    private func startAudioOnQueue(deviceID: String, generation: Int) -> Bool {
        guard generation > stoppedGeneration,
              let device = AVCaptureDevice(uniqueID: deviceID), device.isConnected else { return false }
        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioPreviewOutput()
            output.volume = 1
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                GameLog.log("TV Output: audio session rejected \(device.localizedName)")
                return false
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
        } catch {
            GameLog.log("TV Output: cannot open audio \(device.localizedName): \(error.localizedDescription)")
            return false
        }
        session.startRunning()
        guard session.isRunning, generation > stoppedGeneration else {
            session.stopRunning()
            return false
        }
        audioSession = session
        GameLog.log("TV Output: sound from \(device.localizedName) → default output")
        return true
    }

    // MARK: Stop

    /// Stop both sessions and cancel every start older than `generation`.
    /// Returns immediately; the work runs on the capture queue.
    func stop(generation: Int) {
        queue.async {
            self.stoppedGeneration = max(self.stoppedGeneration, generation)
            self.audioSession?.stopRunning()
            self.audioSession = nil
            self.videoSession?.stopRunning()
            self.videoSession = nil
        }
    }
}
