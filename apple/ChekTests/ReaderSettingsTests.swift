import ChekReader
import Foundation
import Testing
@testable import Chek

/// Reading settings, and the per-series direction kept with them.
struct ReaderSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ChekTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func directionIsKeptPerSeries() {
        let settings = ReaderSettings(defaults: freshDefaults())
        settings.setReadingDirection(.rightToLeft, for: "series/a")
        #expect(settings.preferences(for: "series/a").readingProgression == .rightToLeft)
        #expect(settings.preferences(for: "series/b").readingProgression == nil)
        settings.setReadingDirection(nil, for: "series/a")
        #expect(settings.preferences(for: "series/a").readingProgression == nil)
    }

    @Test func directionSurvivesRelaunch() {
        let defaults = freshDefaults()
        ReaderSettings(defaults: defaults).setReadingDirection(.leftToRight, for: "series/a")
        #expect(ReaderSettings(defaults: defaults).readingDirection(for: "series/a") == .leftToRight)
    }

    @Test func textSizeStepsStayInRange() {
        let settings = ReaderSettings(defaults: freshDefaults())
        for _ in 0..<40 { settings.makeTextLarger() }
        #expect(settings.fontScale <= ReaderPreferences.fontScaleRange.upperBound + 0.001)
        for _ in 0..<40 { settings.makeTextSmaller() }
        #expect(settings.fontScale >= ReaderPreferences.fontScaleRange.lowerBound - 0.001)
    }
}
