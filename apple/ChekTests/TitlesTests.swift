import Foundation
import Testing
@testable import Chek

/// Titles made from what files and sources give.
struct TitlesTests {
    @Test func fileNamesBecomeWords() {
        #expect(BookImporter.title(fromFileName: "peppercarrot_episode01") == "Peppercarrot Episode01")
        #expect(BookImporter.title(fromFileName: "pride-and-prejudice") == "Pride And Prejudice")
    }

    @Test func numbersKeepTheirPunctuation() {
        #expect(BookImporter.title(fromFileName: "volume-3.5") == "Volume 3.5")
        #expect(BookImporter.title(fromFileName: "chapter_1-2") == "Chapter 1-2")
    }

    @Test func existingCapitalsAreKept() {
        #expect(BookImporter.title(fromFileName: "MURAI_iPad") == "MURAI iPad")
    }

    @Test func chapterTitlesCombineNumberAndTitle() {
        #expect(ChekAPI.SourceChapter(id: "a", title: "", number: "12", published: nil).displayTitle == "Chapter 12")
        #expect(ChekAPI.SourceChapter(id: "a", title: "The Title", number: "12", published: nil).displayTitle == "12 · The Title")
        #expect(ChekAPI.SourceChapter(id: "a", title: "Chapter 12: Loki", number: "12", published: nil).displayTitle == "Chapter 12: Loki")
        #expect(ChekAPI.SourceChapter(id: "a", title: "  ", number: nil, published: nil).displayTitle == "Chapter")
    }
}

/// The line under a source series' title.
struct SeriesDetailTests {
    @Test func joinsWhatIsKnown() {
        #expect(SourceSeriesHeader.detail(count: 97, status: "ongoing", year: 2018) == "97 chapters · Ongoing · 2018")
        #expect(SourceSeriesHeader.detail(count: 1, status: "completed", year: nil) == "1 chapter · Completed")
        #expect(SourceSeriesHeader.detail(count: 0, status: nil, year: 1989) == "1989")
        #expect(SourceSeriesHeader.detail(count: 0, status: "weird", year: nil) == nil)
    }
}
