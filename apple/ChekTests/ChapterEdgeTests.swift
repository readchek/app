import ChekReader
import Foundation
import Testing
@testable import Chek

/// The pages the reader gives a chapter's ends, from what's either side.
struct ChapterEdgeTests {
    private let chapter = NeighborLookup.found(.book(UUID(), title: "Two"))

    @Test func aChapterEitherSideIsReadThrough() {
        #expect(chapter.edgePage(at: .end) == .through)
        #expect(chapter.edgePage(at: .start) == .through)
    }

    @Test func theEndStopsWhileNothingFurtherIsKnown() {
        for lookup in [NeighborLookup.looking, .end, .caughtUp, .unknown] {
            #expect(lookup.edgePage(at: .end) == .stop)
            #expect(lookup.edgePage(at: .start) == .none)
        }
    }

    @Test func aBookOutsideASeriesHasNoEndPages() {
        #expect(NeighborLookup.none.edgePage(at: .end) == .none)
        #expect(NeighborLookup.none.edgePage(at: .start) == .none)
    }
}
