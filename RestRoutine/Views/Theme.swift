import SwiftUI

/// Colors, fonts and shapes for the chosen theme in the current appearance.
struct Theme: Equatable {
    let settings: ThemeSettings
    let isDark: Bool
    /// Increase Contrast is on: borders and secondary text get stronger.
    var highContrast = false

    var preset: ThemePreset { settings.preset }

    // MARK: Colors

    private var surfaces: [UInt32] {
        switch (preset, isDark) {
        //                 background  surface     sidebar     line        ink         muted
        case (.dusk, false): [0xF5EFE5, 0xFFFAF2, 0xEAE1D4, 0xD5C7B7, 0x302A26, 0x6D5E52]
        case (.dusk, true): [0x211E1B, 0x2D2823, 0x191714, 0x5E5145, 0xF3E9DB, 0xC6B7A5]
        case (.studio, false): [0xEDF3F1, 0xFBFFFD, 0xDCE8E3, 0xBECFC8, 0x243532, 0x52655E]
        case (.studio, true): [0x172322, 0x22302D, 0x121B1A, 0x455F57, 0xE3EEE9, 0xB2C9BF]
        case (.signal, false): [0xF0F0F5, 0xFCFCFF, 0xE0E1EA, 0xC4C6D5, 0x292B3A, 0x585D74]
        case (.signal, true): [0x191B25, 0x232634, 0x13151E, 0x51586E, 0xE9EAFA, 0xB8BFD6]
        }
    }

    private var accents: (accent: UInt32, tint: UInt32) {
        switch (settings.accent, isDark) {
        case (.ember, false): (0x9B492D, 0xEFE0D3)
        case (.ember, true): (0xEEAA85, 0x443228)
        case (.moss, false): (0x42634A, 0xE0E8DA)
        case (.moss, true): (0xA6C996, 0x2E3C2B)
        case (.ocean, false): (0x236878, 0xD8E9EA)
        case (.ocean, true): (0x8BCDD6, 0x273E42)
        case (.iris, false): (0x6453A3, 0xE7E1F4)
        case (.iris, true): (0xC2B2EF, 0x363047)
        }
    }

    var background: Color { Color(hex: surfaces[0]) }
    var surface: Color { Color(hex: surfaces[1]) }
    var sidebar: Color { Color(hex: surfaces[2]) }
    var line: Color { Color(hex: surfaces[highContrast ? 5 : 3]) }
    var ink: Color { Color(hex: surfaces[4]) }
    var muted: Color { Color(hex: surfaces[5]) }
    var accent: Color { Color(hex: accents.accent) }
    /// A soft fill in the accent's hue.
    var tint: Color { Color(hex: accents.tint) }
    /// Text and symbols drawn on an accent fill.
    var onAccent: Color { surface }
    var danger: Color { Color(hex: isDark ? 0xF5A5A5 : 0xA32F32) }

    // MARK: Shape and spacing

    var cornerRadius: CGFloat {
        switch preset {
        case .dusk: 18
        case .studio: 24
        case .signal: 4
        }
    }

    /// Buttons and sidebar items. Kept under half their height so the shape stays a rounded rectangle.
    var controlRadius: CGFloat {
        switch preset {
        case .dusk: 9
        case .studio: 12
        case .signal: 4
        }
    }

    var panelPadding: CGFloat { preset == .signal ? 16 : 20 }
    var screenPadding: CGFloat { preset == .signal ? 22 : 26 }
    var spacing: CGFloat { preset == .signal ? 14 : 18 }

    // MARK: Type

    private var headingDesign: Font.Design {
        switch settings.headings {
        case .serif: .serif
        case .rounded: .rounded
        case .system: .default
        }
    }

    func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: settings.headings == .serif ? .medium : .semibold, design: headingDesign)
    }

    /// Large figures such as the sleep estimate. Quiet signal uses monospaced values.
    func figure(_ size: CGFloat) -> Font {
        preset == .signal
            ? .system(size: size, weight: .medium, design: .monospaced)
            : heading(size).monospacedDigit()
    }

    /// Values in detail rows, with aligned digits.
    var value: Font {
        preset == .signal ? .system(.body, design: .monospaced) : .body.monospacedDigit()
    }

    var kicker: Font {
        preset == .signal ? .system(size: 10.5, weight: .semibold, design: .monospaced) : .system(size: 10.5, weight: .semibold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(settings: .initial, isDark: false)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Reads the saved theme and applies it below. Every window and sheet root
/// uses it, so a change in Settings reaches all of them at once.
struct ThemeRoot: ViewModifier {
    @AppStorage(PreferenceKey.themePreset) private var preset: String?
    @AppStorage(PreferenceKey.themeAppearance) private var appearance: String?
    @AppStorage(PreferenceKey.themeAccent) private var accent: String?
    @AppStorage(PreferenceKey.themeHeadings) private var headings: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let settings = ThemeSettings(preset: preset, appearance: appearance, accent: accent, headings: headings)
        let dark = switch settings.appearance {
        case .system: colorScheme == .dark
        case .light: false
        case .dark: true
        }
        let theme = Theme(settings: settings, isDark: dark, highContrast: contrast == .increased)
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .foregroundStyle(theme.ink)
            .background(WindowAppearance(mode: settings.appearance))
    }
}

/// Applies the Appearance choice to the window showing this view, and gives
/// the window back its own appearance for Follow system. (preferredColorScheme
/// does not return a Mac window to the system appearance once it has set one.)
private struct WindowAppearance: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.mode = mode
    }

    final class AppearanceView: NSView {
        var mode: AppearanceMode = .system {
            didSet { if mode != oldValue { apply() } }
        }
        private var original: NSAppearance?
        private var overriding = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            switch mode {
            case .system:
                if overriding {
                    window.appearance = original
                    overriding = false
                }
            case .light, .dark:
                if !overriding {
                    original = window.appearance
                    overriding = true
                }
                window.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
            }
        }
    }
}

extension View {
    func themeRoot() -> some View { modifier(ThemeRoot()) }

    /// A themed card surface.
    func themePanel() -> some View { modifier(PanelSurface()) }

    /// The screen's heading names it, so the toolbar does not repeat the title (macOS 15 and later).
    @ViewBuilder func hidesToolbarTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

private struct PanelSurface: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    // Soft studio sits on a thin lip instead of an outline.
                    if theme.preset == .studio { shape.fill(theme.line).offset(y: 2) }
                    shape.fill(theme.surface)
                }
            }
            .overlay {
                if theme.preset != .studio || theme.highContrast {
                    shape.strokeBorder(theme.line, lineWidth: 1)
                }
            }
            .overlay(alignment: .top) {
                if theme.preset == .signal {
                    theme.accent.frame(height: 3)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.cornerRadius,
                                                          topTrailingRadius: theme.cornerRadius))
                }
            }
    }
}

/// A card with an optional heading.
struct ThemePanel<Content: View>: View {
    @Environment(\.theme) private var theme
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(theme.heading(18))
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
            }
            content
        }
        .padding(theme.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themePanel()
    }
}

/// A screen's heading, with an optional subtitle and actions at the trailing edge.
struct ScreenHeader<Actions: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.heading(28))
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(theme.muted)
                }
            }
            Spacer(minLength: 12)
            actions
        }
    }
}

extension ScreenHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A label and value separated by a rule above, as in the sleep and date details.
struct ThemeLine: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String
    var muted = false

    init(_ label: String, _ value: String, muted: Bool = false) {
        self.label = label
        self.value = value
        self.muted = muted
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(theme.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(theme.value)
                .foregroundStyle(muted ? theme.muted : theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { theme.line.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// A small uppercase label above a figure.
struct Kicker: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(theme.kicker)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(theme.muted)
    }
}

/// A themed horizontal rule.
struct ThemeRule: View {
    @Environment(\.theme) private var theme
    var body: some View { theme.line.frame(height: 1) }
}

struct ThemeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        ThemeButton(configuration: configuration, kind: kind)
    }

    private struct ThemeButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let kind: Kind

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: theme.controlRadius)
            configuration.label
                .font(.body.weight(kind == .primary ? .semibold : .regular))
                .foregroundStyle(kind == .primary ? theme.onAccent : kind == .destructive ? theme.danger : theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(shape.fill(kind == .primary ? theme.accent : theme.surface))
                .overlay(shape.strokeBorder(kind == .primary ? theme.accent : theme.line, lineWidth: 1))
                .contentShape(shape)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        }
    }
}

extension ButtonStyle where Self == ThemeButtonStyle {
    static func themed(_ kind: ThemeButtonStyle.Kind = .secondary) -> ThemeButtonStyle {
        ThemeButtonStyle(kind: kind)
    }
}
