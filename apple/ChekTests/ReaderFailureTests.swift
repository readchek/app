import ChekReader
import Foundation
import Testing
@testable import Chek

/// The reader engine's developer-facing errors, as the reader sees them.
struct ReaderFailureTests {
    @Test func networkFailureShowsTheInnermostReason() {
        let error = DisplayError(reader: .network(reason: "The publication could not be downloaded: The page source couldn't say how many pages it has: You're signed out of this server."), kind: .comic)
        #expect(error.title == "Couldn't Load This Comic")
        #expect(error.message == "You're signed out of this server.")
    }

    @Test func networkFailureWithNoReasonSuggestsTheConnection() {
        let error = DisplayError(reader: .network(reason: ""), kind: .book)
        #expect(error.title == "Couldn't Load This Book")
        #expect(error.message == "Check your internet connection and try again.")
    }

    @Test func unsupportedFormatsSaySo() {
        let error = DisplayError(reader: .unsupportedFormat(fileName: "x.xyz"), kind: .book)
        #expect(error.title == "Can't Open This Book")
        #expect(error.message == "Chek doesn't support this kind of file.")
    }

    @Test func damagedFilesKeepTheirReason() {
        let error = DisplayError(reader: .malformed(reason: "no spine"), kind: .book)
        #expect(error.title == "Couldn't Open This Book")
        #expect(error.message == "no spine")
    }
}
