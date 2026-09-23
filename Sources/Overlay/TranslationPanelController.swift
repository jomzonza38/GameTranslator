import AppKit
import SwiftUI
import Combine

// MARK: - Data Model

/// Holds the translation entries displayed in the floating panel
@MainActor
final class TranslationPanelData: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let original: String
        let translated: String
        let regionColor: RegionColor?
        let regionName: String?
    }

    @Published var entries: [Entry] = []
    @Published var isCollapsed = false

    func update(from regions: [TranslatedRegion]) {
        // Sort by vertical position (top to bottom) for natural reading order
        let sorted = regions.sorted { $0.screenRect.minY < $1.screenRect.minY }
        entries = sorted.map {
            Entry(
                original: $0.originalText,
                translated: $0.translatedText,
                regionColor: $0.regionColor,
                regionName: $0.regionName
            )
        }
    }

    func clear() {
        entries = []
    }
}

// MARK: - SwiftUI Content View

/// Width of the region chip row's content (for drag-to-scroll limits)
private struct ChipRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The SwiftUI view rendered inside the floating panel
struct TranslationPanelContent: View {
    @ObservedObject var data: TranslationPanelData
    @ObservedObject private var settings = AppSettings.shared

    // Region chip row: horizontal offset (≤ 0) and sizes for drag-to-scroll
    @State private var chipOffset: CGFloat = 0
    @State private var chipDragStartOffset: CGFloat?
    @State private var chipDidDrag = false
    @State private var chipViewportWidth: CGFloat = 0
    @State private var chipContentWidth: CGFloat = 0
    let onClose: () -> Void

    var body: some View {
        if data.isCollapsed {
            collapsedView
        } else {
            expandedView
        }
    }

    // MARK: - Collapsed View (thin strip)

    private var collapsedView: some View {
        VStack(spacing: 0) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 36, height: 36)

            if !data.entries.isEmpty {
                Text("\(data.entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                data.isCollapsed = false
            }
        }
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                Text("คำแปล")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text("\(data.entries.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)

                // Collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        data.isCollapsed = true
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("ย่อแผง")

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            Divider()
                .background(Color.white.opacity(0.1))

            // Region on/off toggles
            if !settings.captureRegions.isEmpty {
                regionToggles
                Divider()
                    .background(Color.white.opacity(0.1))
            }

            // Translation entries
            if data.entries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.3))
                    Text("กำลังรอข้อความ...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(data.entries) { entry in
                            translationRow(entry)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Region Toggles

    /// One chip per region — click a chip to show/hide that region's translations.
    /// When there are more chips than fit, drag the row left/right with the mouse
    /// (or use the ‹ › buttons). No scroll bar.
    private var regionToggles: some View {
        HStack(spacing: 2) {
            scrollButton("chevron.left", enabled: chipOffset < 0) {
                moveChips(by: 120)
            }

            GeometryReader { geometry in
                HStack(spacing: 6) {
                    ForEach(settings.captureRegions) { region in
                        regionChip(region)
                    }
                }
                .fixedSize()
                .background(
                    GeometryReader { content in
                        Color.clear.preference(key: ChipRowWidthKey.self, value: content.size.width)
                    }
                )
                .offset(x: chipOffset)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(chipDragGesture)
                .onAppear { chipViewportWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in
                    chipViewportWidth = width
                    chipOffset = clampedChipOffset(chipOffset)
                }
            }
            .frame(height: 30)
            .onPreferenceChange(ChipRowWidthKey.self) { width in
                chipContentWidth = width
                chipOffset = clampedChipOffset(chipOffset)
            }

            scrollButton("chevron.right", enabled: chipOffset > minChipOffset) {
                moveChips(by: -120)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var chipDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if chipDragStartOffset == nil {
                    chipDragStartOffset = chipOffset
                }
                chipDidDrag = true
                chipOffset = clampedChipOffset((chipDragStartOffset ?? 0) + value.translation.width)
            }
            .onEnded { _ in
                chipDragStartOffset = nil
                // Let the tap that ends a drag be ignored, then accept taps again
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    chipDidDrag = false
                }
            }
    }

    /// Most negative offset — the last chip's right edge at the viewport's right edge
    private var minChipOffset: CGFloat {
        min(0, chipViewportWidth - chipContentWidth)
    }

    private func clampedChipOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(minChipOffset, offset))
    }

    private func moveChips(by delta: CGFloat) {
        withAnimation(.easeInOut(duration: 0.2)) {
            chipOffset = clampedChipOffset(chipOffset + delta)
        }
    }

    private func regionChip(_ region: CaptureRegion) -> some View {
        HStack(spacing: 4) {
            Image(systemName: region.isEnabled ? "eye.fill" : "eye.slash")
                .font(.system(size: 9))
            Text(region.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(region.isEnabled ? .white : .white.opacity(0.4))
        .background(
            Capsule()
                .fill(Color(nsColor: region.color.nsColor).opacity(region.isEnabled ? 0.45 : 0.08))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: region.color.nsColor).opacity(region.isEnabled ? 0.9 : 0.35), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard !chipDidDrag else { return }
            settings.toggleRegion(id: region.id)
        }
        .help(region.isEnabled ? "ซ่อน \(region.name)" : "แสดง \(region.name)")
    }

    private func scrollButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.6 : 0.15))
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Row

    private func translationRow(_ entry: TranslationPanelData.Entry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Color indicator bar (left border)
            if let regionColor = entry.regionColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: regionColor.nsColor))
                    .frame(width: 4)
                    .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Region name label (if from a specific region)
                if let regionName = entry.regionName, let regionColor = entry.regionColor {
                    Text(regionName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(nsColor: regionColor.nsColor).opacity(0.8))
                        .padding(.bottom, 1)
                }

                // Thai translation
                Text(entry.translated)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // English original
                Text(entry.original)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Panel Controller

/// Controls the floating translation panel window
@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private var panelWindow: NSWindow?
    private let panelData = TranslationPanelData()
    private var cancellables = Set<AnyCancellable>()

    /// Expanded panel size
    private let expandedWidth: CGFloat = 320
    private let panelHeight: CGFloat = 500

    /// Collapsed strip width
    private let collapsedWidth: CGFloat = 44

    /// Distance from screen edge to trigger collapse
    private let edgeThreshold: CGFloat = 15

    // MARK: - Show / Hide

    func show(near windowFrame: CGRect? = nil) {
        if panelWindow == nil {
            createPanel()
        }

        guard let panel = panelWindow else { return }

        if let gameFrame = windowFrame {
            positionPanel(near: gameFrame)
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()

        // Observe collapsed state to resize the window
        panelData.$isCollapsed
            .removeDuplicates()
            .sink { [weak self] collapsed in
                self?.animateCollapseState(collapsed)
            }
            .store(in: &cancellables)
    }

    func hide() {
        cancellables.removeAll()
        panelWindow?.orderOut(nil)
        panelData.clear()
    }

    // MARK: - Update

    func updateRegions(_ regions: [TranslatedRegion]) {
        panelData.update(from: regions)
    }

    // MARK: - Window Setup

    private func createPanel() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "คำแปล"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0.12, alpha: 0.92)
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: collapsedWidth, height: 200)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        let contentView = TranslationPanelContent(
            data: panelData,
            onClose: { [weak self] in
                self?.hide()
            }
        )

        window.contentView = NSHostingView(
            rootView: contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
        )

        panelWindow = window
    }

    // MARK: - Positioning

    /// Position the panel to the right of the game window (or left if no room)
    private func positionPanel(near gameFrame: CGRect) {
        // Convert game frame from CG (top-left origin) to NS (bottom-left origin) and
        // place the panel on the display the game is on
        let gameNSFrame = ScreenCoordinates.appKitRect(fromCG: gameFrame)
        guard let panel = panelWindow,
              let screen = ScreenCoordinates.screen(showingMostOf: gameNSFrame) else { return }

        let screenFrame = screen.visibleFrame
        let gameNSY = gameNSFrame.origin.y

        // Try right side first
        let rightX = gameFrame.maxX + 12
        if rightX + expandedWidth <= screenFrame.maxX {
            panel.setFrameOrigin(NSPoint(x: rightX, y: gameNSY))
            return
        }

        // Try left side
        let leftX = gameFrame.origin.x - expandedWidth - 12
        if leftX >= screenFrame.minX {
            panel.setFrameOrigin(NSPoint(x: leftX, y: gameNSY))
            return
        }

        // Fallback: right edge of screen
        panel.setFrameOrigin(NSPoint(
            x: screenFrame.maxX - expandedWidth - 20,
            y: gameNSY
        ))
    }

    // MARK: - Edge Detection & Collapse

    func windowDidMove(_ notification: Notification) {
        // No auto-collapse — user controls collapse/expand via the button
    }

    /// Called when the user closes the panel via the title bar close button
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false // We handle hiding ourselves
    }

    // MARK: - Collapse Animation

    private func animateCollapseState(_ collapsed: Bool) {
        guard let window = panelWindow else { return }

        let currentFrame = window.frame
        let newWidth = collapsed ? collapsedWidth : expandedWidth

        // Keep the window anchored at its current edge
        let newX: CGFloat
        if let screen = window.screen ?? NSScreen.main {
            let screenMidX = screen.frame.midX
            if currentFrame.midX > screenMidX {
                // Window is on the right half — anchor right edge
                newX = currentFrame.maxX - newWidth
            } else {
                // Window is on the left half — anchor left edge
                newX = currentFrame.origin.x
            }
        } else {
            newX = currentFrame.origin.x
        }

        let newFrame = NSRect(
            x: newX,
            y: currentFrame.origin.y,
            width: newWidth,
            height: currentFrame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}
