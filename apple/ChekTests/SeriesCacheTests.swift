import Foundation
import Testing
@testable import Chek

/// What's kept of a series finds the chapters either side of one, so the
/// reader's previous and next buttons work offline.
struct SeriesCacheTests {
    private func snapshot(_ chapters: [SeriesCache.KnownChapter]) -> SeriesCache.Snapshot {
        let series = ChekAPI.SourceSeries(id: "s", title: "T", summary: nil, coverUrl: nil, contributors: [], readingDirection: nil)
        return SeriesCache.Snapshot(series: series, total: 10, chapters: chapters, savedAt: .now)
    }

    @Test func findsTheChaptersEitherSide() {
        let kept = snapshot((1...3).map { SeriesCache.KnownChapter(position: $0, chapter: ChekAPI.SourceChapter(id: "c\($0)", title: "")) })
        #expect(kept.chapter(before: "c2")?.chapter.id == "c1")
        #expect(kept.chapter(after: "c2")?.chapter.id == "c3")
        #expect(kept.chapter(before: "c1") == nil)
        #expect(kept.chapter(after: "c3") == nil)
    }

    /// A chapter with three releases takes three positions, so the one
    /// before the chapter after it is found past all of them.
    @Test func stepsOverGroupedReleases() {
        let releases = (1...3).map { ChekAPI.SourceRelease(id: "r\($0)", title: "", releaseGroup: "G\($0)") }
        let kept = snapshot([
            SeriesCache.KnownChapter(position: 1, chapter: ChekAPI.SourceChapter(id: "r1", title: "", releases: releases)),
            SeriesCache.KnownChapter(position: 4, chapter: ChekAPI.SourceChapter(id: "c4", title: "")),
        ])
        #expect(kept.chapter(before: "c4")?.chapter.id == "r1")
        #expect(kept.chapter(after: "r2")?.chapter.id == "c4")
    }

    /// A gap in what was seen isn't bridged: the chapter in between is
    /// unknown, not the one past it.
    @Test func doesNotSkipChaptersNeverSeen() {
        let kept = snapshot([
            SeriesCache.KnownChapter(position: 1, chapter: ChekAPI.SourceChapter(id: "c1", title: "")),
            SeriesCache.KnownChapter(position: 3, chapter: ChekAPI.SourceChapter(id: "c3", title: "")),
        ])
        #expect(kept.chapter(before: "c3") == nil)
        #expect(kept.chapter(after: "c1") == nil)
    }
}
