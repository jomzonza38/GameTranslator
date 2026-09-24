import Foundation

// MARK: - Supporting Types

enum PipelineStatus: String {
    case idle = "Idle"
    case capturing = "Capturing..."
    case running = "Running"
    /// First OCR of this launch is still waiting for Vision to prepare its model
    case preparingOCR = "Preparing OCR"
    case error = "Error"

    var displayName: String {
        switch self {
        case .idle: return "พร้อมใช้งาน"
        case .capturing: return "กำลังจับภาพ..."
        case .running: return "กำลังทำงาน"
        case .preparingOCR: return "กำลังเตรียม OCR ครั้งแรก… (อาจนานถึง ~1 นาที)"
        case .error: return "เกิดข้อผิดพลาด"
        }
    }
}

struct PipelineStats {
    var avgOCRTime: Double = 0
    var avgTranslateTime: Double = 0
    var avgTotalTime: Double = 0
    var totalFramesProcessed: Int = 0
    var totalTextsDetected: Int = 0
    var totalTextsTranslated: Int = 0

    private var ocrTimes: [Double] = []
    private var translateTimes: [Double] = []
    private var totalTimes: [Double] = []

    mutating func update(ocrTime: Double, translateTime: Double, totalTime: Double,
                         textsDetected: Int, textsTranslated: Int) {
        totalFramesProcessed += 1
        totalTextsDetected += textsDetected
        totalTextsTranslated += textsTranslated

        ocrTimes.append(ocrTime)
        translateTimes.append(translateTime)
        totalTimes.append(totalTime)

        if ocrTimes.count > 30 {
            ocrTimes.removeFirst()
            translateTimes.removeFirst()
            totalTimes.removeFirst()
        }

        avgOCRTime = ocrTimes.reduce(0, +) / Double(ocrTimes.count)
        avgTranslateTime = translateTimes.reduce(0, +) / Double(translateTimes.count)
        avgTotalTime = totalTimes.reduce(0, +) / Double(totalTimes.count)
    }
}

enum PipelineError: LocalizedError {
    case invalidWindow
    case captureNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidWindow: return "เลือก window ไม่ถูกต้อง"
        case .captureNotAvailable: return "ไม่สามารถจับภาพหน้าจอได้ กรุณาตรวจสอบสิทธิ์ Screen Recording"
        }
    }
}
