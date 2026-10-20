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
