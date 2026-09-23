import SwiftUI
import ScreenCaptureKit

/// SwiftUI view for selecting which game window to capture
struct WindowPickerView: View {
    let windows: [SCWindow]
    let onSelect: (SCWindow) -> Void

    @State private var searchText = ""
    @State private var hoveredId: CGWindowID?

    var filteredWindows: [SCWindow] {
        if searchText.isEmpty {
            return windows
        }
        return windows.filter { window in
            let title = window.title ?? ""
            let appName = window.owningApplication?.applicationName ?? ""
            let query = searchText.lowercased()
            return title.lowercased().contains(query) || appName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("เลือก Game Window")
                    .font(.headline)

                Text("เลือกหน้าต่างเกมที่ต้องการแปลข้อความ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("ค้นหา...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
            }
            .padding()

            Divider()

            // Window list
            if filteredWindows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("ไม่พบหน้าต่างที่เปิดอยู่")
                        .foregroundStyle(.secondary)
                    Text("กรุณาเปิดเกมก่อนแล้วลองใหม่")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredWindows, id: \.windowID) { window in
                            WindowRow(window: window, isHovered: hoveredId == window.windowID)
                                .onTapGesture {
                                    onSelect(window)
                                }
                                .onHover { isHovered in
                                    hoveredId = isHovered ? window.windowID : nil
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 400)
    }
}

/// A single window row in the picker
private struct WindowRow: View {
    let window: SCWindow
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            Image(systemName: "macwindow")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(window.owningApplication?.applicationName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}
