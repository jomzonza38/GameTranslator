import SwiftUI

/// SwiftUI settings window
struct SettingsWindow: View {
    @ObservedObject var pipeline: PipelineCoordinator
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            TranslationSettingsTab(pipeline: pipeline)
                .tabItem {
                    Label("การแปล", systemImage: "character.book.closed")
                }

            GameSettingsTab()
                .tabItem {
                    Label("เกม", systemImage: "gamecontroller")
                }

            CaptureSettingsTab()
                .tabItem {
                    Label("การจับภาพ", systemImage: "camera.viewfinder")
                }

            OverlaySettingsTab(pipeline: pipeline)
                .tabItem {
                    Label("Overlay", systemImage: "text.bubble")
                }

            StatsTab(pipeline: pipeline)
                .tabItem {
                    Label("สถิติ", systemImage: "chart.bar")
                }
        }
        .frame(minWidth: 480, minHeight: 400)
        .padding()
    }
}

// MARK: - Translation Settings

private struct TranslationSettingsTab: View {
    @ObservedObject var pipeline: PipelineCoordinator
    @ObservedObject private var settings = AppSettings.shared
    @State private var isTestingKey = false
    @State private var testResultMessage: String?
    @State private var testResultSuccess: Bool?

    var body: some View {
        Form {
            Section("Translation Provider") {
                Picker("Provider:", selection: $settings.selectedProvider) {
                    ForEach(AppSettings.TranslationProviderType.allCases) { provider in
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                        }
                        .tag(provider)
                    }
                }
                .onChange(of: settings.selectedProvider) { _, _ in
                    pipeline.updateProvider()
                }

                // Provider limit info
                Text(settings.selectedProvider.limitDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ภาษา") {
                Picker("ภาษาในเกม:", selection: $settings.sourceLanguage) {
                    ForEach(AppSettings.SourceLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Text(settings.sourceLanguage.requiresAccurateOCR
                     ? "แปลเป็นภาษาไทย — ภาษานี้ใช้ OCR โหมดแม่นยำเสมอ"
                     : "แปลเป็นภาษาไทย")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API Keys") {
                if settings.selectedProvider == .openAI {
                    APIKeyField(title: "OpenAI API Key:", key: $settings.openAIApiKey) {
                        pipeline.updateProvider()
                    }

                    Link("สมัคร OpenAI API Key",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)

                    Text("ใช้ GPT-4o-mini — แปลเป็นธรรมชาติ เหมือนคนไทยพูดจริงๆ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.selectedProvider == .claudeHaiku {
                    APIKeyField(title: "Anthropic API Key:", key: $settings.claudeApiKey) {
                        pipeline.updateProvider()
                    }

                    Link("สมัคร Anthropic API Key",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)

                    Text("ใช้ Claude Haiku — แปลเป็นธรรมชาติ เหมือนคนไทยพูดจริงๆ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.selectedProvider == .deeplFree || settings.selectedProvider == .deeplPro {
                    APIKeyField(title: "DeepL API Key:", key: $settings.deeplApiKey) {
                        pipeline.updateProvider()
                    }

                    Link("สมัคร DeepL API Key (ฟรี)",
                         destination: URL(string: "https://www.deepl.com/pro-api")!)
                        .font(.caption)
                }

                if settings.selectedProvider == .googleCloud {
                    APIKeyField(title: "Google Cloud API Key:", key: $settings.googleCloudApiKey) {
                        pipeline.updateProvider()
                    }

                    Link("สร้าง Google Cloud API Key",
                         destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .font(.caption)
                }

                if settings.selectedProvider == .googleFree {
                    Text("ไม่ต้องใช้ API Key")
                        .foregroundStyle(.secondary)
                }

                // Test API Key button
                if settings.selectedProvider.requiresApiKey {
                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            testCurrentApiKey()
                        } label: {
                            Label("ทดสอบ API Key", systemImage: "network")
                        }
                        .disabled(isTestingKey || currentApiKey.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if isTestingKey {
                            ProgressView()
                                .controlSize(.small)
                            Text("กำลังทดสอบ...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let msg = testResultMessage, let success = testResultSuccess {
                        HStack(spacing: 4) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text(msg)
                                .lineLimit(3)
                        }
                        .font(.caption)
                        .foregroundStyle(success ? .green : .red)
                        .padding(.vertical, 2)
                    }
                }
            }

            // Only DeepL Free counts characters (it has a 500K/month limit)
            if settings.selectedProvider == .deeplFree {
                Section("การใช้งาน DeepL Free") {
                    HStack {
                        Text("ใช้ไปแล้วเดือนนี้:")
                        Spacer()
                        Text("\(formatNumber(settings.monthlyCharacterCount)) ตัวอักษร")
                            .foregroundStyle(settings.isNearLimit() ? .red : .primary)
                    }

                    if let remaining = settings.remainingCharacters {
                        HStack {
                            Text("เหลือ:")
                            Spacer()
                            Text("\(formatNumber(remaining)) ตัวอักษร")
                                .foregroundStyle(remaining < 50_000 ? .red : .green)
                        }

                        ProgressView(value: Double(settings.monthlyCharacterCount), total: 500_000)
                            .tint(settings.isNearLimit() ? .red : .blue)
                    }

                    Button("รีเซ็ตตัวนับ") {
                        settings.monthlyCharacterCount = 0
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var currentApiKey: String {
        switch settings.selectedProvider {
        case .claudeHaiku: return settings.claudeApiKey
        case .openAI: return settings.openAIApiKey
        case .deeplFree, .deeplPro: return settings.deeplApiKey
        case .googleCloud: return settings.googleCloudApiKey
        case .googleFree: return ""
        }
    }

    private func testCurrentApiKey() {
        isTestingKey = true
        testResultMessage = nil
        testResultSuccess = nil

        Task {
            do {
                let provider = TranslationService.createProvider(
                    for: settings.selectedProvider,
                    settings: settings
                )
                let result = try await provider.translate("Hello", from: "en", to: "th")
                testResultMessage = "ใช้ได้! \"Hello\" → \"\(result)\"" 
                testResultSuccess = true
            } catch {
                testResultMessage = error.localizedDescription
                testResultSuccess = false
            }
            isTestingKey = false
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Capture Settings

private struct CaptureSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("อัตราการจับภาพ") {
                HStack {
                    Text("Frame Rate:")
                    Slider(value: $settings.captureFrameRate, in: 1...10, step: 1) {
                        Text("FPS")
                    }
                    Text("\(Int(settings.captureFrameRate)) FPS")
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }

                Text("ค่าที่แนะนำ: 3-5 FPS (สมดุลระหว่างความเร็วและ CPU)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OCR") {
                Picker("ความแม่นยำ:", selection: $settings.ocrAccuracy) {
                    ForEach(AppSettings.OCRAccuracy.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(settings.sourceLanguage.requiresAccurateOCR)

                Text(settings.sourceLanguage.requiresAccurateOCR
                     ? "ภาษา \(settings.sourceLanguage.displayName) ใช้โหมดแม่นยำเสมอ (Vision โหมดเร็วรองรับเฉพาะอักษรละติน)"
                     : settings.ocrAccuracy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("ความมั่นใจขั้นต่ำ:")
                    Slider(value: Binding(
                        get: { Double(settings.minimumConfidence) },
                        set: { settings.minimumConfidence = Float($0) }
                    ), in: 0.1...0.9, step: 0.1)
                    Text(String(format: "%.0f%%", settings.minimumConfidence * 100))
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }

                Text("ค่าต่ำ = ตรวจจับได้มากขึ้นแต่อาจมี noise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("พื้นที่แปล") {
                if settings.captureRegions.isEmpty {
                    HStack {
                        Image(systemName: "rectangle.dashed")
                            .foregroundStyle(.secondary)
                        Text("ยังไม่มีพื้นที่ — ใช้เมนู \"🔲 เลือกพื้นที่แปล\" ขณะกำลังแปลอยู่")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.captureRegions.enumerated()), id: \.element.id) { index, region in
                        Toggle(isOn: Binding(
                            get: { region.isEnabled },
                            set: { _ in settings.toggleRegion(id: region.id) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(nsColor: region.color.nsColor))
                                    .frame(width: 8, height: 8)
                                Text(region.name)
                                if index < 9 {
                                    Text("⌃⌥\(index + 1)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.caption)
                    }

                    Button("ล้างพื้นที่ทั้งหมด") {
                        settings.removeAllRegions()
                    }
                    .font(.caption)
                }

                Text("เลือกแปลเฉพาะบริเวณ dialog หรือ subtitle เพื่อลด noise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Overlay Settings

private struct OverlaySettingsTab: View {
    @ObservedObject var pipeline: PipelineCoordinator
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("โหมดแสดงผล") {
                Picker("โหมด:", selection: $settings.displayMode) {
                    ForEach(AppSettings.DisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.displayMode) { _, _ in
                    pipeline.switchDisplayMode()
                }

                if settings.displayMode == .overlay {
                    Text("แสดงคำแปลซ้อนทับบนหน้าจอเกมโดยตรง")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("แสดงคำแปลในกล่องข้อความลอย — ลากไปขอบจอเพื่อย่อ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("การแสดงผล") {
                Toggle("ปรับขนาดตัวอักษรอัตโนมัติ", isOn: $settings.autoFontSize)

                if !settings.autoFontSize {
                    HStack {
                        Text("ขนาดตัวอักษร:")
                        Slider(value: $settings.overlayFontSize, in: 10...48, step: 1)
                        Text("\(Int(settings.overlayFontSize)) pt")
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                }

                HStack {
                    Text("ความทึบข้อความ:")
                    Slider(value: $settings.overlayOpacity, in: 0.3...1.0, step: 0.1)
                    Text(String(format: "%.0f%%", settings.overlayOpacity * 100))
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("ความทึบพื้นหลัง:")
                    Slider(value: $settings.overlayBackgroundOpacity, in: 0.0...1.0, step: 0.1)
                    Text(String(format: "%.0f%%", settings.overlayBackgroundOpacity * 100))
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Section("ตัวเลือกเพิ่มเติม") {
                Toggle("แสดงข้อความต้นฉบับด้วย", isOn: $settings.showOriginalText)

                Text("แสดงข้อความต้นฉบับใต้คำแปลภาษาไทย")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("แสดงภาพข้อความต้นฉบับในแผงคำแปล", isOn: $settings.showSourceThumbnails)

                Text("โหมดแผงคำแปล แบบแปลทั้งหน้าต่าง: แต่ละคำแปลมีภาพข้อความจากเกมให้ดูว่ามาจากตรงไหน")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("เลื่อนแผงคำแปลไปที่ข้อความที่ชี้ในเกม", isOn: $settings.panelFollowsGamePointer)

                Text("โหมดแผงคำแปล: วางเมาส์บนข้อความในเกมครู่หนึ่ง แผงจะเลื่อนไปที่คำแปลนั้นและไฮไลต์ไว้")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("แสดงหน้าต้อนรับตอนเปิดแอป", isOn: $settings.showWelcomeOnLaunch)

                Text("บอกว่าแอปทำงานแล้วและไอคอนอยู่ตรงไหนบนแถบเมนู")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Stats Tab

private struct StatsTab: View {
    @ObservedObject var pipeline: PipelineCoordinator

    var body: some View {
        Form {
            Section("Performance") {
                StatsRow(label: "เฟรมที่ประมวลผล", value: "\(pipeline.stats.totalFramesProcessed)")
                StatsRow(label: "ข้อความที่ตรวจพบ", value: "\(pipeline.stats.totalTextsDetected)")
                StatsRow(label: "ข้อความที่แปล", value: "\(pipeline.stats.totalTextsTranslated)")

                Divider()

                StatsRow(label: "OCR เฉลี่ย",
                         value: String(format: "%.0f ms", pipeline.stats.avgOCRTime * 1000))
                StatsRow(label: "แปลภาษาเฉลี่ย",
                         value: String(format: "%.0f ms", pipeline.stats.avgTranslateTime * 1000))
                StatsRow(label: "รวมเฉลี่ย",
                         value: String(format: "%.0f ms", pipeline.stats.avgTotalTime * 1000))
            }

            Section("สถานะ") {
                StatsRow(label: "Provider", value: pipeline.isRunning ? "Active" : "Idle")
                StatsRow(label: "Overlay regions", value: "\(pipeline.currentRegions.count)")
            }
        }
        .formStyle(.grouped)
    }
}

private struct StatsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - API Key Field

/// SecureField for an API key. Typing edits a local draft; the key is saved (trimmed)
/// only when editing ends — Return, focus leaving the field, the field going away
/// (window closed, other provider picked) or a 1 s pause in typing. Saving writes the
/// Keychain and rebuilds the provider, which must not happen on every keystroke.
private struct APIKeyField: View {
    let title: String
    @Binding var key: String
    let onSave: () -> Void

    @State private var draft = ""
    @State private var pendingSave: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear { draft = key }
            .onChange(of: key) { _, newKey in
                // Loaded from the Keychain after the field appeared
                if !isFocused { draft = newKey }
            }
            .onChange(of: draft) { _, _ in saveAfterPause() }
            .onChange(of: isFocused) { _, focused in
                if !focused { save() }
            }
            .onSubmit { save() }
            .onDisappear { save() }
    }

    private func saveAfterPause() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let value = APIKeyInput.valueToSave(draft: draft, current: key) else { return }
        key = value
        onSave()
    }
}
