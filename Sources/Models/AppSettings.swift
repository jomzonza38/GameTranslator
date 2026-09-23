import Foundation
import CoreGraphics

/// Persisted app settings backed by UserDefaults (API keys live in the Keychain)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Translation Provider

    enum TranslationProviderType: String, CaseIterable, Identifiable {
        case googleFree = "google_free"
        case openAI = "openai"
        case claudeHaiku = "claude_haiku"
        case deeplFree = "deepl_free"
        case deeplPro = "deepl_pro"
        case googleCloud = "google_cloud"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .googleFree: return "Google Translate (Free)"
            case .openAI: return "OpenAI GPT-4o-mini"
            case .claudeHaiku: return "Claude Haiku 4.5"
            case .deeplFree: return "DeepL Free"
            case .deeplPro: return "DeepL Pro"
            case .googleCloud: return "Google Cloud Translation"
            }
        }

        var limitDescription: String {
            switch self {
            case .googleFree: return "ฟรี ไม่ต้องใช้ API Key (อาจถูก rate limit)"
            case .openAI: return "~$0.15/1M tokens — แปลเป็นธรรมชาติ เหมือนคนพูดจริง"
            case .claudeHaiku: return "$1 input / $5 output ต่อ 1M tokens — แปลเป็นธรรมชาติ เหมือนคนพูดจริง"
            case .deeplFree: return "500,000 ตัวอักษร/เดือน (ฟรี, ต้องสมัคร API Key)"
            case .deeplPro: return "ไม่จำกัด (€5.49/เดือน + €25/ล้านตัวอักษร)"
            case .googleCloud: return "$20/ล้านตัวอักษร (ต้องมี GCP project)"
            }
        }

        var requiresApiKey: Bool {
            switch self {
            case .googleFree: return false
            default: return true
            }
        }
    }

    // MARK: - Display Mode

    enum DisplayMode: String, CaseIterable, Identifiable {
        case overlay = "overlay"
        case panel = "panel"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .overlay: return "Overlay (ซ้อนทับหน้าจอ)"
            case .panel: return "Panel (กล่องข้อความ)"
            }
        }
    }

    // MARK: - OCR Accuracy

    enum OCRAccuracy: String, CaseIterable, Identifiable {
        case fast = "fast"
        case accurate = "accurate"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fast: return "เร็ว (Fast)"
            case .accurate: return "แม่นยำ (Accurate)"
            }
        }

        var detail: String {
            switch self {
            case .fast: return "~50-100ms ต่อเฟรม เหมาะกับข้อความตัวใหญ่ พื้นหลังเรียบ"
            case .accurate: return "~200-300ms ต่อเฟรม อ่านฟอนต์เกมและพื้นหลังลายได้ดีกว่า แนะนำ FPS 2-3"
            }
        }
    }

    @Published var selectedProvider: TranslationProviderType {
        didSet { defaults.set(selectedProvider.rawValue, forKey: "selectedProvider") }
    }

    @Published var deeplApiKey: String {
        didSet { KeychainStore.set(deeplApiKey, for: "deeplApiKey") }
    }

    @Published var googleCloudApiKey: String {
        didSet { KeychainStore.set(googleCloudApiKey, for: "googleCloudApiKey") }
    }

    @Published var openAIApiKey: String {
        didSet { KeychainStore.set(openAIApiKey, for: "openAIApiKey") }
    }

    @Published var claudeApiKey: String {
        didSet { KeychainStore.set(claudeApiKey, for: "claudeApiKey") }
    }

    // MARK: - Capture Settings

    @Published var captureFrameRate: Double {
        didSet { defaults.set(captureFrameRate, forKey: "captureFrameRate") }
    }

    // MARK: - Overlay Settings

    @Published var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: "overlayOpacity") }
    }

    @Published var overlayFontSize: Double {
        didSet { defaults.set(overlayFontSize, forKey: "overlayFontSize") }
    }

    @Published var overlayBackgroundOpacity: Double {
        didSet { defaults.set(overlayBackgroundOpacity, forKey: "overlayBackgroundOpacity") }
    }

    @Published var autoFontSize: Bool {
        didSet { defaults.set(autoFontSize, forKey: "autoFontSize") }
    }

    // MARK: - Usage Tracking

    @Published var monthlyCharacterCount: Int {
        didSet { defaults.set(monthlyCharacterCount, forKey: "monthlyCharacterCount") }
    }

    @Published var usageResetDate: Date {
        didSet { defaults.set(usageResetDate.timeIntervalSince1970, forKey: "usageResetDate") }
    }

    // MARK: - General

    @Published var ocrAccuracy: OCRAccuracy {
        didSet { defaults.set(ocrAccuracy.rawValue, forKey: "ocrAccuracy") }
    }

    @Published var minimumConfidence: Float {
        didSet { defaults.set(minimumConfidence, forKey: "minimumConfidence") }
    }

    @Published var showOriginalText: Bool {
        didSet { defaults.set(showOriginalText, forKey: "showOriginalText") }
    }

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") }
    }

    // MARK: - Capture Regions (multiple)

    @Published var captureRegions: [CaptureRegion] {
        didSet { saveCaptureRegions() }
    }

    // MARK: - Init

    private init() {
        let providerRaw = defaults.string(forKey: "selectedProvider") ?? TranslationProviderType.googleFree.rawValue
        self.selectedProvider = TranslationProviderType(rawValue: providerRaw) ?? .googleFree

        self.deeplApiKey = Self.loadApiKey("deeplApiKey", defaults: defaults)
        self.googleCloudApiKey = Self.loadApiKey("googleCloudApiKey", defaults: defaults)
        self.openAIApiKey = Self.loadApiKey("openAIApiKey", defaults: defaults)
        self.claudeApiKey = Self.loadApiKey("claudeApiKey", defaults: defaults)

        self.captureFrameRate = defaults.double(forKey: "captureFrameRate").nonZero ?? 5.0

        self.overlayOpacity = defaults.double(forKey: "overlayOpacity").nonZero ?? 1.0
        self.overlayFontSize = defaults.double(forKey: "overlayFontSize").nonZero ?? 16.0
        self.overlayBackgroundOpacity = defaults.double(forKey: "overlayBackgroundOpacity").nonZero ?? 0.6
        self.autoFontSize = defaults.object(forKey: "autoFontSize") as? Bool ?? true

        self.monthlyCharacterCount = defaults.integer(forKey: "monthlyCharacterCount")
        let resetInterval = defaults.double(forKey: "usageResetDate")
        self.usageResetDate = resetInterval > 0 ? Date(timeIntervalSince1970: resetInterval) : Date()

        self.minimumConfidence = defaults.object(forKey: "minimumConfidence") as? Float ?? 0.5
        self.ocrAccuracy = OCRAccuracy(rawValue: defaults.string(forKey: "ocrAccuracy") ?? "") ?? .fast
        self.showOriginalText = defaults.object(forKey: "showOriginalText") as? Bool ?? false

        let modeRaw = defaults.string(forKey: "displayMode") ?? DisplayMode.overlay.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .overlay

        // Load capture regions
        self.captureRegions = []
        self.captureRegions = loadCaptureRegions()

        checkAndResetMonthlyUsage()
    }

    // MARK: - API Key Storage

    /// Load an API key from the Keychain. Keys saved by older versions in
    /// UserDefaults are moved into the Keychain and removed from UserDefaults.
    private static func loadApiKey(_ account: String, defaults: UserDefaults) -> String {
        if let legacy = defaults.string(forKey: account) {
            if legacy.isEmpty {
                defaults.removeObject(forKey: account)
            } else if KeychainStore.set(legacy, for: account) {
                // Only drop the plaintext copy once the Keychain write succeeded
                defaults.removeObject(forKey: account)
                GameLog.log("Migrated \(account) from UserDefaults to Keychain")
                return legacy
            } else {
                return legacy
            }
        }
        return KeychainStore.get(account) ?? ""
    }

    // MARK: - Capture Regions Persistence

    private func saveCaptureRegions() {
        let dicts = captureRegions.map { $0.toDictionary() }
        defaults.set(dicts, forKey: "captureRegions_v2")
    }

    private func loadCaptureRegions() -> [CaptureRegion] {
        // Try new format first
        if let dicts = defaults.array(forKey: "captureRegions_v2") as? [[String: Any]] {
            return dicts.compactMap { CaptureRegion(from: $0) }
        }

        // Migrate from old single-region format
        if defaults.bool(forKey: "captureRegionEnabled"),
           let dict = defaults.dictionary(forKey: "captureRegion"),
           let x = dict["x"] as? Double,
           let y = dict["y"] as? Double,
           let w = dict["w"] as? Double,
           let h = dict["h"] as? Double {
            let region = CaptureRegion(
                name: "Region 1",
                rect: CGRect(x: x, y: y, width: w, height: h),
                color: .blue
            )
            // Save in new format and clear old keys
            let result = [region]
            let dicts = result.map { $0.toDictionary() }
            defaults.set(dicts, forKey: "captureRegions_v2")
            defaults.removeObject(forKey: "captureRegion")
            defaults.removeObject(forKey: "captureRegionEnabled")
            return result
        }

        return []
    }

    /// The next color to assign to a new region (cycles through palette)
    var nextRegionColor: RegionColor {
        let usedColors = Set(captureRegions.map(\.color))
        // Pick first unused color, or cycle
        return RegionColor.allCases.first(where: { !usedColors.contains($0) })
            ?? RegionColor.allCases[captureRegions.count % RegionColor.allCases.count]
    }

    /// Auto-generated name for the next region
    var nextRegionName: String {
        "Region \(captureRegions.count + 1)"
    }

    func addRegion(_ region: CaptureRegion) {
        captureRegions.append(region)
    }

    func removeRegion(id: UUID) {
        captureRegions.removeAll { $0.id == id }
    }

    func removeAllRegions() {
        captureRegions.removeAll()
    }

    func renameRegion(id: UUID, to newName: String) {
        if let index = captureRegions.firstIndex(where: { $0.id == id }) {
            captureRegions[index].name = newName
        }
    }

    func moveRegion(id: UUID, direction: Int) {
        guard let index = captureRegions.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < captureRegions.count else { return }
        captureRegions.swapAt(index, newIndex)
    }

    // MARK: - Usage Tracking

    func addCharacterUsage(_ count: Int) {
        checkAndResetMonthlyUsage()
        monthlyCharacterCount += count
    }

    func isNearLimit() -> Bool {
        guard selectedProvider == .deeplFree else { return false }
        return monthlyCharacterCount > 450_000 // 90% of 500K
    }

    func isAtLimit() -> Bool {
        guard selectedProvider == .deeplFree else { return false }
        return monthlyCharacterCount >= 500_000
    }

    var remainingCharacters: Int? {
        guard selectedProvider == .deeplFree else { return nil }
        return max(0, 500_000 - monthlyCharacterCount)
    }

    private func checkAndResetMonthlyUsage() {
        let calendar = Calendar.current
        if !calendar.isDate(usageResetDate, equalTo: Date(), toGranularity: .month) {
            monthlyCharacterCount = 0
            usageResetDate = Date()
        }
    }
}

// MARK: - Double Extension
extension Double {
    /// Returns self if non-zero, otherwise nil (for UserDefaults default handling)
    var nonZero: Double? {
        self != 0 ? self : nil
    }
}
