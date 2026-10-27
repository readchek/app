import Foundation
import Testing
@testable import Chek

/// The app's theme, and how iOS's icon names map to the icons offered.
struct AppearanceSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ChekTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func themeStartsAsChek() {
        let settings = AppearanceSettings(defaults: freshDefaults(), alternateIconName: nil)
        #expect(settings.theme == .chek)
    }

    @Test func themeSurvivesRelaunch() {
        let defaults = freshDefaults()
        AppearanceSettings(defaults: defaults, alternateIconName: nil).theme = .chibiManga
        #expect(AppearanceSettings(defaults: defaults, alternateIconName: nil).theme == .chibiManga)
    }

    @Test func iconFollowsTheNameIOSReports() {
        #expect(AppearanceSettings(defaults: freshDefaults(), alternateIconName: "ChibiManga").icon == .chibiManga)
        #expect(AppearanceSettings(defaults: freshDefaults(), alternateIconName: nil).icon == .chek)
    }

    @Test func unknownIconNameMeansThePrimaryIcon() {
        #expect(AppIcon(alternateName: "Retired") == .chek)
    }

    @Test func everyIconRoundTripsThroughItsName() {
        for icon in AppIcon.allCases {
            #expect(AppIcon(alternateName: icon.alternateName) == icon)
        }
    }
}
