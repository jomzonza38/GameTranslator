import AppKit
import SwiftUI
import Combine

// MARK: - Data Model

/// Holds the translation entries displayed in the floating panel
@MainActor
final class TranslationPanelData: ObservableObject {
    struct Entry: Identifiable {
        /// Stable across updates — region + source text + occurrence — so the hovered
        /// entry survives the per-frame refresh (T-0019)
        let id: String
        let original: String
        let translated: String
        let regionColor: RegionColor?
        let regionName: String?
        /// Picture of the original text (full-screen mode only)
        let thumbnail: CGImage?
        /// Where the original text is on screen (CG screen coordinates)
        let sourceRect: CGRect
    }

    /// Outline to draw around the hovered entry's source text
    struct SourceHighlight: Equatable {
        /// CG screen coordinates
        let rect: CGRect
        /// Region colour; nil in full-screen mode
        let regionColor: RegionColor?
    }

    @Published var entries: [Entry] = []
    @Published var isCollapsed = false
    /// First OCR of this launch is waiting for Vision to prepare its model
    @Published var isPreparingOCR = false

    /// Entry the mouse is over (by `Entry.id`)
    @Published private(set) var hoveredID: String?
    /// Entry whose text the mouse rests on in the game (T-0021)
    @Published private(set) var pointedID: String?
    /// Outline for the hovered entry's source text (nil = nothing to outline)
    @Published private(set) var highlight: SourceHighlight?

    func update(from regions: [TranslatedRegion]) {
        // Sort by vertical position (top to bottom) for natural reading order
        let sorted = regions.sorted { $0.screenRect.minY < $1.screenRect.minY }
        var occurrences: [String: Int] = [:]
        entries = sorted.map {
            let base = "\($0.regionID?.uuidString ?? "full")|\($0.originalText)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return Entry(
                id: "\(base)#\(occurrence)",
                original: $0.originalText,
                translated: $0.translatedText,
                regionColor: $0.regionColor,
                regionName: $0.regionName,
                thumbnail: $0.sourceThumbnail,
                sourceRect: $0.sourceRect
            )
        }
        // Hovered text gone from the screen: drop the hover; otherwise follow it
        if let hoveredID, !entries.contains(where: { $0.id == hoveredID }) {
            self.hoveredID = nil
        }
        if let pointedID, !entries.contains(where: { $0.id == pointedID }) {
            self.pointedID = nil
        }
        refreshHighlight()
    }

    /// Mark the entry whose text the mouse rests on in the game (nil = none)
    func setPointed(_ id: String?) {
        let valid = id.flatMap { id in entries.contains { $0.id == id } ? id : nil }
        if valid != pointedID {
            pointedID = valid
        }
    }

    /// Mouse entered or left an entry's row
    func setHovered(_ id: String, isInside: Bool) {
        if isInside {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
        refreshHighlight()
    }

    func clear() {
        entries = []
        hoveredID = nil
        pointedID = nil
        refreshHighlight()
    }

    private func refreshHighlight() {
        let entry = entries.first { $0.id == hoveredID }
        let newHighlight = entry.map { SourceHighlight(rect: $0.sourceRect, regionColor: $0.regionColor) }
        if newHighlight != highlight {
            highlight = newHighlight
        }
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
                    Text(data.isPreparingOCR ? "กำลังเตรียม OCR ครั้งแรก… (อาจนานถึง ~1 นาที)" : "กำลังรอข้อความ...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(data.entries) { entry in
                                translationRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    // Mouse rests on a text in the game → bring its translation into view
                    .onChange(of: data.pointedID) { _, pointed in
                        guard let pointed else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(pointed, anchor: .center)
                        }
                    }
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

                // Picture of the original text in the game (full-screen mode)
                if entry.regionColor == nil, settings.showSourceThumbnails, let thumbnail = entry.thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 24, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .padding(.bottom, 2)
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
                .fill(Color.white.opacity(data.hoveredID == entry.id || data.pointedID == entry.id ? 0.10 : 0.03))
        )
        // Pointing at an entry outlines its text in the game (T-0019)
        .onHover { isInside in
            data.setHovered(entry.id, isInside: isInside)
        }
    }
}

// MARK: - Panel Controller

/// Controls the floating translation panel window
@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private var panelWindow: NSWindow?
    private let panelData = TranslationPanelData()
    private var cancellables = Set<AnyCancellable>()
    /// Click-through outline around the hovered entry's source text (T-0019)
    private let sourceHighlight = SourceHighlightWindow()
    private var highlightSubscription: AnyCancellable?
    /// Polls the mouse position while the panel is shown (T-0021). `NSEvent.mouseLocation`
    /// needs no permission — no event tap, no Accessibility / Input Monitoring.
    private var pointerTimer: Timer?
    private var pointerTracker = PointerRestTracker()

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
        startPointerTracking()

        // Draw / move / remove the outline as the hovered entry changes
        if highlightSubscription == nil {
            highlightSubscription = panelData.$highlight
                .removeDuplicates()
                .sink { [weak self] highlight in
                    guard let self else { return }
                    if let highlight {
                        self.sourceHighlight.show(
                            around: highlight.rect,
                            color: highlight.regionColor?.nsColor ?? .systemYellow
                        )
                    } else {
                        self.sourceHighlight.hide()
                    }
                }
        }

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
        stopPointerTracking()
        panelWindow?.orderOut(nil)
        panelData.clear()
        // Stop, game closed, Overlay mode: never leave an outline behind
        sourceHighlight.hide()
    }

    // MARK: - Game pointer (T-0021)

    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        pointerTracker.reset()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        pointerTracker.reset()
    }

    /// One sample: which translated game text is the mouse resting on?
    private func trackPointer() {
        guard AppSettings.shared.panelFollowsGamePointer,
              let panel = panelWindow, panel.isVisible,
              !panelData.isCollapsed, !panelData.entries.isEmpty else {
            if panelData.pointedID != nil { panelData.setPointed(nil) }
            pointerTracker.reset()
            return
        }

        let mouse = NSEvent.mouseLocation
        // Over the panel itself: hovering its rows (T-0019) wins
        guard !panel.frame.contains(mouse),
              let primary = NSScreen.screens.first else { return }

        let point = ScreenCoordinates.cgPoint(fromAppKit: mouse, primaryDisplayHeight: primary.frame.height)
        let hit = GamePointer.entryID(at: point, in: panelData.entries.map { ($0.id, $0.sourceRect) })
        let selected = pointerTracker.update(hit: hit, at: point, now: CFAbsoluteTimeGetCurrent())
        if selected != panelData.pointedID {
            panelData.setPointed(selected)
        }
    }

    // MARK: - Update

    func updateRegions(_ regions: [TranslatedRegion]) {
        panelData.update(from: regions)
    }

    /// Show "preparing OCR" instead of "waiting for text" while the first OCR runs
    func setPreparingOCR(_ preparing: Bool) {
        if panelData.isPreparingOCR != preparing {
            panelData.isPreparingOCR = preparing
        }
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
