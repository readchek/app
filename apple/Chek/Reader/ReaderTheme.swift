import ChekReader
import SwiftUI

/// The colors of a reading theme, matching the ones the reader script
/// paints the page with.
struct ReaderTheme {
    let theme: ReaderPreferences.Theme

    init(_ theme: ReaderPreferences.Theme) {
        self.theme = theme
    }

    var background: Color {
        switch theme {
        case .original, .light: Color(red: 1, green: 1, blue: 1)
        case .sepia: Color(red: 0xF5 / 255, green: 0xEC / 255, blue: 0xD9 / 255)
        case .dark: Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
        }
    }

    var text: Color {
        switch theme {
        case .original, .light: Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
        case .sepia: Color(red: 0x4B / 255, green: 0x3A / 255, blue: 0x26 / 255)
        case .dark: Color(red: 0xE8 / 255, green: 0xE6 / 255, blue: 0xE3 / 255)
        }
    }

    /// The color scheme controls drawn over the page should use.
    var colorScheme: ColorScheme {
        theme == .dark ? .dark : .light
    }

    var name: LocalizedStringResource {
        switch theme {
        case .original: "Original"
        case .light: "Light"
        case .sepia: "Sepia"
        case .dark: "Dark"
        }
    }
}
