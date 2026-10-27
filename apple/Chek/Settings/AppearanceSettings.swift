import Foundation
import Observation
import UIKit

/// The app's theme, kept between launches, and its home screen icon,
/// which iOS keeps.
@MainActor
@Observable
final class AppearanceSettings {
    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }

    /// The icon iOS shows, read at launch and updated once iOS has
    /// changed it.
    private(set) var icon: AppIcon

    private let defaults: UserDefaults
    private static let themeKey = "appTheme"

    init(defaults: UserDefaults = .standard, alternateIconName: String? = UIApplication.shared.alternateIconName) {
        self.defaults = defaults
        theme = defaults.string(forKey: Self.themeKey).flatMap(AppTheme.init(rawValue:)) ?? .chek
        icon = AppIcon(alternateName: alternateIconName)
    }

    /// Whether iOS lets this device change the icon.
    var canChangeIcon: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Asks iOS to change the home screen icon. iOS tells the reader it
    /// changed, so there's nothing to show here; if it refuses, the
    /// icon stays as it was and so does the choice in Settings.
    func setIcon(_ icon: AppIcon) async {
        guard icon != self.icon, canChangeIcon else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            self.icon = icon
        } catch {
            self.icon = AppIcon(alternateName: UIApplication.shared.alternateIconName)
        }
    }
}
