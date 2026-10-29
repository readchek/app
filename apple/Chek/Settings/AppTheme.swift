import SwiftUI
import UIKit

/// The color the app's controls take, chosen in Settings.
enum AppTheme: String, CaseIterable, Identifiable {
    case chek
    /// Chibi Manga's green, for readers who came from it and miss it.
    case chibiManga

    var id: Self { self }

    /// The tint every control takes. It lives in the asset catalog so it
    /// has a lighter shade in dark mode.
    var tint: Color { Color(colorName) }

    /// The same tint for UIKit, which draws alerts and menus.
    var uiTint: UIColor? { UIColor(named: colorName) }

    private var colorName: String {
        switch self {
        case .chek: "AccentColor"
        case .chibiManga: "ChibiMangaAccent"
        }
    }
}

/// The home screen icons Chek offers. iOS keeps which one is chosen.
enum AppIcon: String, CaseIterable, Identifiable {
    case chek
    /// Chibi Manga's cat, so readers who came from it can keep it.
    case chibiManga

    var id: Self { self }

    /// The icon iOS reports for an alternate icon name, nil being the
    /// primary icon. A name Chek no longer ships falls back to it too.
    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .chek
    }

    /// The icon set's name in the asset catalog, listed in the target's
    /// alternate app icon names. Nil for the primary icon.
    var alternateName: String? {
        switch self {
        case .chek: nil
        case .chibiManga: "ChibiManga"
        }
    }

    /// A small copy of the icon to show in Settings, since an app can't
    /// load its own icon sets as images.
    var previewImageName: String {
        switch self {
        case .chek: "ChekIconPreview"
        case .chibiManga: "ChibiMangaIconPreview"
        }
    }
}

extension View {
    /// Tints this view, and the windows UIKit draws alerts and menus in,
    /// with the chosen theme.
    func appTheme() -> some View {
        modifier(AppThemeModifier())
    }
}

private struct AppThemeModifier: ViewModifier {
    @Environment(AppearanceSettings.self) private var appearance

    func body(content: Content) -> some View {
        content
            .tint(appearance.theme.tint)
            .onChange(of: appearance.theme, initial: true) { _, theme in
                // Alerts and confirmation dialogs take the window's tint,
                // which otherwise stays the asset catalog's accent.
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows {
                        window.tintColor = theme.uiTint
                    }
                }
            }
    }
}
