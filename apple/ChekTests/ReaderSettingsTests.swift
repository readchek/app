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

    @Test func commentsAreOnUntilTurnedOff() {
        let defaults = freshDefaults()
        #expect(ReaderSettings(defaults: defaults).showsComments)
        ReaderSettings(defaults: defaults).showsComments = false
        #expect(!ReaderSettings(defaults: defaults).showsComments)
    }

    @Test func hiddenCommentersAreKeptPerSite() {
        let defaults = freshDefaults()
        let settings = ReaderSettings(defaults: defaults)
        settings.setHidden(true, "Ana", on: "page.chek.a", siteName: "A")
        #expect(settings.isHidden("Ana", on: "page.chek.a"))
        #expect(!settings.isHidden("Ana", on: "page.chek.b"))
        let relaunched = ReaderSettings(defaults: defaults)
        #expect(relaunched.isHidden("Ana", on: "page.chek.a"))
        #expect(relaunched.commentSites["page.chek.a"] == "A")
        relaunched.setHidden(false, "Ana", on: "page.chek.a")
        #expect(relaunched.hiddenCommenters.isEmpty)
    }
}
