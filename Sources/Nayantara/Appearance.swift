import AppKit
import Observation
import SwiftUI

/// The "Font Size" setting. macOS ignores SwiftUI's dynamicTypeSize, so text is
/// scaled by hand: every text style goes through `scaledFont`, which multiplies
/// the style's system point size by `scale`.
enum FontSize: String, CaseIterable, Identifiable {
    case small, standard, large, extraLarge, huge

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .huge: "Huge"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.3
        case .huge: 1.5
        }
    }
}

@Observable
@MainActor
final class Appearance {
    static let shared = Appearance()

    /// The popover's width at the default size; it grows with the text.
    static let baseWidth: CGFloat = 380

    var fontSize = FontSize(rawValue: UserDefaults.standard.string(forKey: "fontSize") ?? "") ?? .standard {
        didSet {
            UserDefaults.standard.set(fontSize.rawValue, forKey: "fontSize")
            DetachedWindow.shared.fitWidth()
        }
    }

    var scale: CGFloat { fontSize.scale }
    var width: CGFloat { Self.baseWidth * scale }
}

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.fontScale) private var scale
    let style: NSFont.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        let base = NSFont.preferredFont(forTextStyle: style).pointSize
        // macOS's headline is the bold one; keep that unless told otherwise.
        let w = weight ?? (style == .headline ? .bold : .regular)
        return content.font(.system(size: (base * scale).rounded(), weight: w))
    }
}

extension View {
    /// Like `.font(.callout)`, but sized by the Font Size setting.
    func scaledFont(_ style: NSFont.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight))
    }
}
