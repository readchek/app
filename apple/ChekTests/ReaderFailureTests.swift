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

/// The sentences failure screens build from an error, which used to glue
/// a title to the next sentence or say "try again" twice.
@MainActor
struct FailureSentenceTests {
    @Test func titleAloneBecomesASentence() {
        #expect(DisplayError(title: "Site Turned Off").sentence == "Site Turned Off.")
        #expect(DisplayError(title: "A", message: "Try again later.").sentence == "Try again later.")
    }

    @Test func tryAgainIsSaidOnce() {
        let offline = DisplayError(ChekError.offline(URLError(.notConnectedToInternet)))
        let text = String(ReaderFailureMessage.make(for: offline, kind: .comic, canRetry: true).characters)
        #expect(text == "Check your internet connection and try again. You can also close this comic.")
    }

    @Test func tryAgainIsAddedWhenTheErrorDoesNotSayIt() {
        let error = DisplayError(title: "Couldn't Open This Book", message: "The file may be damaged.")
        let text = String(ReaderFailureMessage.make(for: error, kind: .book, canRetry: true).characters)
        #expect(text == "The file may be damaged. Try again. You can also close this book.")
    }

    @Test func somethingGoneOffersNoRetry() {
        let gone = DisplayError(ChekError.notFound)
        #expect(gone.kind == .gone)
        let text = String(ReaderFailureMessage.make(for: gone, kind: .comic, canRetry: true).characters)
        #expect(text == "It may have been moved or removed from the library. Close this comic.")
        let screen = String(FailureState.message(for: gone, canRetry: true).characters)
        #expect(screen == "It may have been moved or removed from the library.")
    }

    @Test func retryLinkGoesOnTheWordsAlreadyThere() {
        let offline = DisplayError(ChekError.offline(URLError(.notConnectedToInternet)))
        let text = FailureState.message(for: offline, canRetry: true)
        let linked = text.runs.filter { $0.link != nil }.map { String(text[$0.range].characters) }
        #expect(linked == ["try again"])
    }

    @Test func symbolsFollowTheKindOfFailure() {
        #expect(DisplayError(ChekError.offline(URLError(.timedOut))).systemImage == "wifi.exclamationmark")
        #expect(DisplayError(ChekError.unauthorized).systemImage == "person.crop.circle.badge.exclamationmark")
        #expect(DisplayError(ChekError.invalidResponse).systemImage == "exclamationmark.circle")
    }
}
