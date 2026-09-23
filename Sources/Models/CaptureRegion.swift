import Foundation
import CoreGraphics
import AppKit

/// Preset colors for translation regions
enum RegionColor: String, CaseIterable {
    case blue, green, orange, purple, pink, yellow, cyan, red

    var nsColor: NSColor {
        switch self {
        case .blue:   return NSColor(red: 0.29, green: 0.62, blue: 1.0, alpha: 1.0)
        case .green:  return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
        case .orange: return NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)
        case .purple: return NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0)
        case .pink:   return NSColor(red: 1.0, green: 0.22, blue: 0.37, alpha: 1.0)
        case .yellow: return NSColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1.0)
        case .cyan:   return NSColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 1.0)
        case .red:    return NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)
        }
    }

    var displayName: String {
        switch self {
        case .blue:   return "น้ำเงิน"
        case .green:  return "เขียว"
        case .orange: return "ส้ม"
        case .purple: return "ม่วง"
        case .pink:   return "ชมพู"
        case .yellow: return "เหลือง"
        case .cyan:   return "ฟ้า"
        case .red:    return "แดง"
        }
    }
}

/// Represents a user-defined screen region to translate
struct CaptureRegion: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Normalized coordinates (0...1), top-left origin
    var rect: CGRect
    var color: RegionColor
    /// Whether this region is translated and shown (toggle without deleting it)
    var isEnabled: Bool

    init(name: String, rect: CGRect, color: RegionColor, isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.rect = rect
        self.color = color
        self.isEnabled = isEnabled
    }

    // MARK: - UserDefaults Serialization

    func toDictionary() -> [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "w": Double(rect.width),
            "h": Double(rect.height),
            "color": color.rawValue,
            "enabled": isEnabled
        ]
    }

    init?(from dict: [String: Any]) {
        guard let idStr = dict["id"] as? String,
              let uuid = UUID(uuidString: idStr),
              let name = dict["name"] as? String,
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double,
              let colorStr = dict["color"] as? String,
              let color = RegionColor(rawValue: colorStr) else {
            return nil
        }
        self.id = uuid
        self.name = name
        self.rect = CGRect(x: x, y: y, width: w, height: h)
        self.color = color
        self.isEnabled = dict["enabled"] as? Bool ?? true
    }
}
