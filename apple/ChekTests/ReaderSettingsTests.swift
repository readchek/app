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

    @Test func readingModeIsKeptPerSeries() {
        let settings = ReaderSettings(defaults: freshDefaults())
        settings.setReadingMode(.manga, for: "series/a")
        #expect(settings.preferences(for: "series/a").readingProgression == .rightToLeft)
        #expect(settings.preferences(for: "series/a").comicFlow == .paged)
        #expect(settings.preferences(for: "series/b").readingProgression == nil)
        #expect(settings.preferences(for: "series/b").comicFlow == .automatic)
        settings.setReadingMode(.automatic, for: "series/a")
        #expect(settings.preferences(for: "series/a").readingProgression == nil)
    }

    @Test func eachReadingModeLaysPagesOutItsWay() {
        let settings = ReaderSettings(defaults: freshDefaults())
        settings.setReadingMode(.comic, for: "a")
        #expect(settings.preferences(for: "a").comicFlow == .paged)
        #expect(settings.preferences(for: "a").readingProgression == .leftToRight)
        settings.setReadingMode(.webtoon, for: "a")
        #expect(settings.preferences(for: "a").comicFlow == .scrolled)
        #expect(settings.preferences(for: "a").readingProgression == nil)
    }

    @Test func readingModeSurvivesRelaunch() {
        let defaults = freshDefaults()
        ReaderSettings(defaults: defaults).setReadingMode(.webtoon, for: "series/a")
        #expect(ReaderSettings(defaults: defaults).readingMode(for: "series/a") == .webtoon)
    }

    @Test func directionsChosenBeforeReadingModesStillApply() {
        let defaults = freshDefaults()
        defaults.set(["series/a": "rtl", "series/b": "ltr"], forKey: "reader.readingDirections")
        let settings = ReaderSettings(defaults: defaults)
        #expect(settings.readingMode(for: "series/a") == .manga)
        #expect(settings.readingMode(for: "series/b") == .comic)
        // Choosing automatic doesn't bring the old direction back.
        settings.setReadingMode(.automatic, for: "series/a")
        #expect(ReaderSettings(defaults: defaults).readingMode(for: "series/a") == .automatic)
    }

    @Test func aSeriesItsSourceCallsAStripScrollsOnAutomatic() {
        let defaults = freshDefaults()
        let settings = ReaderSettings(defaults: defaults)
        StripSeries.note(true, for: "series/a", in: defaults)
        #expect(settings.preferences(for: "series/a").comicFlow == .scrolled)
        #expect(settings.preferences(for: "series/b").comicFlow == .automatic)
        // What the reader chose wins over what the source says.
        settings.setReadingMode(.manga, for: "series/a")
        #expect(settings.preferences(for: "series/a").comicFlow == .paged)
        settings.setReadingMode(.automatic, for: "series/a")
        StripSeries.note(false, for: "series/a", in: defaults)
        #expect(settings.preferences(for: "series/a").comicFlow == .automatic)
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
