import Foundation
import Testing
@testable import Chek

/// Telling a newer version on the App Store from the one running.
struct AppUpdateTests {
    @Test func comparesVersionsByTheirNumbers() {
        #expect(AppUpdateCheck.isNewer("2.3", than: "2.2"))
        #expect(AppUpdateCheck.isNewer("2.10", than: "2.9"))
        #expect(AppUpdateCheck.isNewer("3.0", than: "2.9.9"))
        #expect(AppUpdateCheck.isNewer("2.2.1", than: "2.2"))
        #expect(!AppUpdateCheck.isNewer("2.2", than: "2.2"))
        #expect(!AppUpdateCheck.isNewer("2.2", than: "2.2.0"))
        #expect(!AppUpdateCheck.isNewer("2.1", than: "2.2"))
    }

    @Test func readsTheStoresListing() throws {
        let answer = Data(#"{"resultCount":1,"results":[{"version":"2.3","trackViewUrl":"https://apps.apple.com/us/app/chek/id1?uo=4"}]}"#.utf8)
        let update = try #require(AppUpdateCheck.update(in: answer, installed: "2.2"))
        #expect(update.version == "2.3")
        #expect(update.store.host() == "apps.apple.com")
        // The version running, or a later one from TestFlight, has nothing to offer.
        #expect(AppUpdateCheck.update(in: answer, installed: "2.3") == nil)
        #expect(AppUpdateCheck.update(in: answer, installed: "2.4") == nil)
    }

    @Test func anAnswerWithNoListingOffersNothing() {
        #expect(AppUpdateCheck.update(in: Data(#"{"resultCount":0,"results":[]}"#.utf8), installed: "2.2") == nil)
        #expect(AppUpdateCheck.update(in: Data("not json".utf8), installed: "2.2") == nil)
    }
}
