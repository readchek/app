import Testing
@testable import Chek

/// What the label beside the scrubber says, on a page and past the last one.
struct ScrubberPlaceTests {
    @Test func comicsShowThePage() {
        let place = ScrubberPlace.make(showsPages: true, position: 7, count: 20, progress: 0.3, isAtChapterEnd: false)
        #expect(place == .page(7, of: 20))
    }

    @Test func booksShowHowFarThrough() {
        let place = ScrubberPlace.make(showsPages: false, position: 7, count: 20, progress: 0.3, isAtChapterEnd: false)
        #expect(place == .progress(0.3))
    }

    @Test func chapterEndSaysFinishedInsteadOfTheLastPage() {
        let place = ScrubberPlace.make(showsPages: true, position: 20, count: 20, progress: 1, isAtChapterEnd: true)
        #expect(place == .finished)
    }

    @Test func nothingBeforeThePublicationIsKnown() {
        let place = ScrubberPlace.make(showsPages: true, position: 1, count: 0, progress: nil, isAtChapterEnd: false)
        #expect(place == .none)
    }
}
