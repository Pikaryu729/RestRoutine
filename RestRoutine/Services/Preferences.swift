import Foundation

enum PreferenceKey {
    static let waterUnit = "waterUnit"
    static func reminderEnabled(_ kind: ReminderKind) -> String { "reminder.\(kind.rawValue).enabled" }
    static func reminderHour(_ kind: ReminderKind) -> String { "reminder.\(kind.rawValue).hour" }
    static func reminderMinute(_ kind: ReminderKind) -> String { "reminder.\(kind.rawValue).minute" }
    static let themePreset = "theme.preset"
    static let themeAppearance = "theme.appearance"
    static let themeAccent = "theme.accent"
    static let themeHeadings = "theme.headings"
}

extension UserDefaults {
    var waterUnit: WaterUnit {
        get { string(forKey: PreferenceKey.waterUnit).flatMap(WaterUnit.init(rawValue:)) ?? .milliliters }
        set { set(newValue.rawValue, forKey: PreferenceKey.waterUnit) }
    }
}
