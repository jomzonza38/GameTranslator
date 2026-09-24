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

        /// Keychain account holding this provider's API key (nil = no key needed)
        var keychainAccount: String? {
            switch self {
            case .googleFree: return nil
            case .openAI: return "openAIApiKey"
            case .claudeHaiku: return "claudeApiKey"
            case .deeplFree, .deeplPro: return "deeplApiKey"
            case .googleCloud: return "googleCloudApiKey"
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

    // MARK: - Source Language

    enum SourceLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case japanese = "ja"
        case chineseSimplified = "zh-Hans"
        case chineseTraditional = "zh-Hant"
        case korean = "ko"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english: return "English"
            case .japanese: return "日本語 (ญี่ปุ่น)"
            case .chineseSimplified: return "简体中文 (จีนตัวย่อ)"
            case .chineseTraditional: return "繁體中文 (จีนตัวเต็ม)"
            case .korean: return "한국어 (เกาหลี)"
            }
        }

        /// Name used inside LLM prompts
        var englishName: String {
            switch self {
            case .english: return "English"
            case .japanese: return "Japanese"
            case .chineseSimplified: return "Simplified Chinese"
            case .chineseTraditional: return "Traditional Chinese"
            case .korean: return "Korean"
            }
        }

        /// Language code passed to translation providers (Google-style)
        var translationCode: String {
            switch self {
            case .english: return "en"
            case .japanese: return "ja"
            case .chineseSimplified: return "zh-CN"
            case .chineseTraditional: return "zh-TW"
            case .korean: return "ko"
            }
        }

        /// Languages for Vision text recognition. English is kept as a fallback
        /// because game UIs often mix Latin text into CJK scripts.
        var visionLanguages: [String] {
            switch self {
            case .english: return ["en-US"]
            case .japanese: return ["ja-JP", "en-US"]
            case .chineseSimplified: return ["zh-Hans", "en-US"]
            case .chineseTraditional: return ["zh-Hant", "en-US"]
            case .korean: return ["ko-KR", "en-US"]
            }
        }

        /// Vision's fast recognizer only supports Latin scripts
        var requiresAccurateOCR: Bool { self != .english }

        /// Whether words are separated by spaces (affects merging OCR lines)
        var usesWordSpacing: Bool {
            switch self {
            case .japanese, .chineseSimplified, .chineseTraditional: return false
            case .english, .korean: return true
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
        didSet {
            defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
            loadApiKeyIfNeeded(for: selectedProvider)
        }
    }

    @Published var deeplApiKey: String {
        didSet { storeApiKey(deeplApiKey, account: "deeplApiKey") }
    }

    @Published var googleCloudApiKey: String {
        didSet { storeApiKey(googleCloudApiKey, account: "googleCloudApiKey") }
    }

    @Published var openAIApiKey: String {
        didSet { storeApiKey(openAIApiKey, account: "openAIApiKey") }
    }

    @Published var claudeApiKey: String {
        didSet { storeApiKey(claudeApiKey, account: "claudeApiKey") }
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

    @Published var sourceLanguage: SourceLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: "sourceLanguage") }
    }

    /// OCR level actually used — non-Latin languages always need .accurate
    var effectiveOCRAccuracy: OCRAccuracy {
        sourceLanguage.requiresAccurateOCR ? .accurate : ocrAccuracy
    }

    @Published var ocrAccuracy: OCRAccuracy {
        didSet { defaults.set(ocrAccuracy.rawValue, forKey: "ocrAccuracy") }
    }

    @Published var minimumConfidence: Float {
        didSet { defaults.set(minimumConfidence, forKey: "minimumConfidence") }
    }

    /// Show the "app is running — look at the menu bar" window at launch
    @Published var showWelcomeOnLaunch: Bool {
        didSet { defaults.set(showWelcomeOnLaunch, forKey: "showWelcomeOnLaunch") }
    }

    /// Panel mode: pointing at a text in the game scrolls the panel to its translation (T-0021)
    @Published var panelFollowsGamePointer: Bool {
        didSet { defaults.set(panelFollowsGamePointer, forKey: Self.panelFollowsGamePointerKey) }
    }

    static let panelFollowsGamePointerKey = "panelFollowsGamePointer"

    /// Stored value, on by default
    static func loadPanelFollowsGamePointer(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: panelFollowsGamePointerKey) as? Bool ?? true
    }

    /// Panel (full-screen mode): show a picture of each text's original pixels (T-0018)
    @Published var showSourceThumbnails: Bool {
        didSet { defaults.set(showSourceThumbnails, forKey: Self.showSourceThumbnailsKey) }
    }

    static let showSourceThumbnailsKey = "showSourceThumbnails"

    /// Stored value, on by default
    static func loadShowSourceThumbnails(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showSourceThumbnailsKey) as? Bool ?? true
    }

    @Published var showOriginalText: Bool {
        didSet { defaults.set(showOriginalText, forKey: "showOriginalText") }
    }

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") }
    }

    // MARK: - Game Profiles & Context

    /// Send recent lines to LLM providers so names and tone stay consistent
    @Published var useConversationContext: Bool {
        didSet { defaults.set(useConversationContext, forKey: "useConversationContext") }
    }

    /// Key of the game currently (or most recently) captured — the app name
    @Published var currentGameID: String {
        didSet { defaults.set(currentGameID, forKey: "currentGameID") }
    }

    /// Per-game settings keyed by app name
    @Published var gameProfiles: [String: GameProfile] {
        didSet { saveGameProfiles() }
    }

    /// Profile of the current game (empty profile when no game has been captured yet)
    var currentProfile: GameProfile {
        get { gameProfiles[currentGameID] ?? GameProfile(title: currentGameID) }
        set {
            guard !currentGameID.isEmpty else { return }
            gameProfiles[currentGameID] = newValue
        }
    }

    /// Make `id` the current game, creating a profile for it if needed
    func selectGame(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if gameProfiles[trimmed] == nil {
            gameProfiles[trimmed] = GameProfile(title: trimmed)
        }
        currentGameID = trimmed
    }

    private func saveGameProfiles() {
        if let data = try? JSONEncoder().encode(gameProfiles) {
            defaults.set(data, forKey: "gameProfiles_v1")
        }
    }

    private static func loadGameProfiles(_ defaults: UserDefaults) -> [String: GameProfile] {
        guard let data = defaults.data(forKey: "gameProfiles_v1"),
              let profiles = try? JSONDecoder().decode([String: GameProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }

    // MARK: - Capture Regions (multiple)

    @Published var captureRegions: [CaptureRegion] {
        didSet { saveCaptureRegions() }
    }

    // MARK: - Init

    private init() {
        let providerRaw = defaults.string(forKey: "selectedProvider") ?? TranslationProviderType.googleFree.rawValue
        self.selectedProvider = TranslationProviderType(rawValue: providerRaw) ?? .googleFree

        self.deeplApiKey = ""
        self.googleCloudApiKey = ""
        self.openAIApiKey = ""
        self.claudeApiKey = ""

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
        self.sourceLanguage = SourceLanguage(rawValue: defaults.string(forKey: "sourceLanguage") ?? "") ?? .english
        self.showOriginalText = defaults.object(forKey: "showOriginalText") as? Bool ?? false
        self.showSourceThumbnails = Self.loadShowSourceThumbnails(defaults)
        self.panelFollowsGamePointer = Self.loadPanelFollowsGamePointer(defaults)
        self.showWelcomeOnLaunch = defaults.object(forKey: "showWelcomeOnLaunch") as? Bool ?? true

        let modeRaw = defaults.string(forKey: "displayMode") ?? DisplayMode.overlay.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .overlay

        self.useConversationContext = defaults.object(forKey: "useConversationContext") as? Bool ?? true
        self.currentGameID = defaults.string(forKey: "currentGameID") ?? ""
        self.gameProfiles = Self.loadGameProfiles(defaults)

        // Load capture regions
        self.captureRegions = []
        self.captureRegions = loadCaptureRegions()

        checkAndResetMonthlyUsage()

        // Only the selected provider's key is read now; each Keychain read of an
        // item can trigger a macOS access prompt, so other keys load on demand.
        loadApiKeyIfNeeded(for: selectedProvider)
    }

    // MARK: - API Key Storage

    /// Keychain accounts already read this session
    private var loadedKeyAccounts: Set<String> = []
    /// Set while assigning a value read from the Keychain, so it isn't written back
    private var isLoadingApiKey = false

    /// Read the provider's API key from the Keychain the first time it is needed
    func loadApiKeyIfNeeded(for provider: TranslationProviderType) {
        guard let account = provider.keychainAccount, !loadedKeyAccounts.contains(account) else { return }
        loadedKeyAccounts.insert(account)

        let value = Self.loadApiKey(account, defaults: defaults)
        guard !value.isEmpty else { return }

        isLoadingApiKey = true
        defer { isLoadingApiKey = false }
        switch account {
        case "deeplApiKey": deeplApiKey = value
        case "googleCloudApiKey": googleCloudApiKey = value
        case "openAIApiKey": openAIApiKey = value
        case "claudeApiKey": claudeApiKey = value
        default: break
        }
    }

    private func storeApiKey(_ value: String, account: String) {
        guard !isLoadingApiKey else { return }
        loadedKeyAccounts.insert(account)
        KeychainStore.set(value, for: account)
    }

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
                return APIKeyInput.normalized(legacy)
            } else {
                return APIKeyInput.normalized(legacy)
            }
        }
        return APIKeyInput.normalized(KeychainStore.get(account) ?? "")
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

    /// Regions that are switched on
    var enabledRegions: [CaptureRegion] {
        captureRegions.filter(\.isEnabled)
    }

    /// Show/hide one region's translations without deleting it
    func toggleRegion(id: UUID) {
        if let index = captureRegions.firstIndex(where: { $0.id == id }) {
            captureRegions[index].isEnabled.toggle()
        }
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

// MARK: - API Key Input

/// Rules for turning what the user typed or pasted into the stored API key
enum APIKeyInput {
    /// Pasted keys often carry a trailing space or newline, which the services reject (401)
    static func normalized(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value to save for `draft`, or nil when it would not change the stored key
    static func valueToSave(draft: String, current: String) -> String? {
        let value = normalized(draft)
        return value == current ? nil : value
    }
}
