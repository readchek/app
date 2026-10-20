import ChekReader
import Foundation
import Testing
@testable import Chek

/// The reader engine's developer-facing errors, as the reader sees them.
struct ReaderFailureTests {
    @Test func networkFailureShowsTheInnermostReason() {
        let error = DisplayError(reader: .network(reason: "The publication could not be downloaded: The page source couldn't say how many pages it has: You're signed out of this server."), kind: .comic)
        #expect(error.title == "Couldn't load this comic.")
        #expect(error.message == "You're signed out of this server.")
    }

    @Test func networkFailureWithNoReasonSuggestsTheConnection() {
        let error = DisplayError(reader: .network(reason: ""), kind: .book)
        #expect(error.title == "Couldn't load this book.")
        #expect(error.message == "Check your connection and try again.")
    }

    @Test func unsupportedFormatsSaySo() {
        let error = DisplayError(reader: .unsupportedFormat(fileName: "x.xyz"), kind: .book)
        #expect(error.title == "Chek can't read this book.")
        #expect(error.message == "It isn't in a format Chek reads.")
    }

    @Test func damagedFilesKeepTheirReason() {
        let error = DisplayError(reader: .malformed(reason: "no spine"), kind: .book)
        #expect(error.title == "Couldn't open this book.")
        #expect(error.message == "no spine")
    }
}
