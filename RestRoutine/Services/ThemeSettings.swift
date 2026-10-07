import Foundation

/// The overall look: surfaces, card shape, spacing and decoration.
enum ThemePreset: String, CaseIterable, Identifiable {
    case dusk, studio, signal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dusk: "Dusk journal"
        case .studio: "Soft studio"
        case .signal: "Quiet signal"
        }
    }

    var defaultAccent: ThemeAccent {
        switch self {
        case .dusk: .ember
        case .studio: .ocean
        case .signal: .iris
        }
    }

    var defaultHeadings: HeadingStyle {
        switch self {
        case .dusk: .serif
        case .studio: .rounded
        case .signal: .system
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Follow system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum ThemeAccent: String, CaseIterable, Identifiable {
    case ember, moss, ocean, iris
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ember: "Ember"
        case .moss: "Moss"
        case .ocean: "Ocean"
        case .iris: "Iris"
        }
    }
}

enum HeadingStyle: String, CaseIterable, Identifiable {
    case serif, rounded, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .serif: "Journal · serif"
        case .rounded: "Soft · rounded"
        case .system: "Clean · system"
        }
    }
}

/// The appearance choices kept in preferences. They stay on this Mac and are
/// not part of record backups.
struct ThemeSettings: Equatable {
    var preset: ThemePreset
    var appearance: AppearanceMode
    var accent: ThemeAccent
    var headings: HeadingStyle

    /// The approved starting look, which Reset appearance returns to.
    static let initial = ThemeSettings(preset: .studio, appearance: .system, accent: .ocean, headings: .rounded)

    init(preset: ThemePreset, appearance: AppearanceMode, accent: ThemeAccent, headings: HeadingStyle) {
        self.preset = preset
        self.appearance = appearance
        self.accent = accent
        self.headings = headings
    }

    /// Reads saved values. Missing or unknown ones fall back to the starting
    /// look, or to the saved preset's own accent and headings.
    init(preset: String?, appearance: String?, accent: String?, headings: String?) {
        let resolved = preset.flatMap(ThemePreset.init(rawValue:)) ?? Self.initial.preset
        self.preset = resolved
        self.appearance = appearance.flatMap(AppearanceMode.init(rawValue:)) ?? Self.initial.appearance
        self.accent = accent.flatMap(ThemeAccent.init(rawValue:)) ?? resolved.defaultAccent
        self.headings = headings.flatMap(HeadingStyle.init(rawValue:)) ?? resolved.defaultHeadings
    }

    /// Picking a preset applies its accent and headings, and keeps the appearance mode.
    mutating func choose(_ preset: ThemePreset) {
        self.preset = preset
        accent = preset.defaultAccent
        headings = preset.defaultHeadings
    }
}

extension UserDefaults {
    var themeSettings: ThemeSettings {
        get {
            ThemeSettings(
                preset: string(forKey: PreferenceKey.themePreset),
                appearance: string(forKey: PreferenceKey.themeAppearance),
                accent: string(forKey: PreferenceKey.themeAccent),
                headings: string(forKey: PreferenceKey.themeHeadings))
        }
        set {
            set(newValue.preset.rawValue, forKey: PreferenceKey.themePreset)
            set(newValue.appearance.rawValue, forKey: PreferenceKey.themeAppearance)
            set(newValue.accent.rawValue, forKey: PreferenceKey.themeAccent)
            set(newValue.headings.rawValue, forKey: PreferenceKey.themeHeadings)
        }
    }

    /// Restores the starting look only. Units, reminders and records are untouched.
    func resetTheme() {
        themeSettings = .initial
    }
}
