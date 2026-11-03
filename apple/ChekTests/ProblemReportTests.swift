import Foundation
import Testing
@testable import Chek

/// The bug form link from Settings, with the fields it fills in.
struct ProblemReportTests {
    private func queryItems(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func opensTheBugFormInChek() {
        let url = ProblemReport.url(version: "2.1 (14)", device: "iPhone (iPhone17,1)", system: "iOS 26.1")
        #expect(url.host() == "github.com")
        #expect(url.path() == "/readchek/chek/issues/new")
        #expect(queryItems(of: url)["template"] == "bug.yml")
    }

    @Test func fillsInTheAppsFields() {
        let url = ProblemReport.url(version: "2.1 (14)", device: "iPhone (iPhone17,1)", system: "iOS 26.1")
        let fields = queryItems(of: url)
        #expect(fields["area"] == "iPhone or iPad app")
        #expect(fields["version"] == "App 2.1 (14)")
        #expect(fields["device"] == "iPhone (iPhone17,1) on iOS 26.1")
    }

    @Test func fieldsSurviveTheQuery() throws {
        // Spaces, parentheses and commas all have to come back as typed.
        let url = ProblemReport.url(version: "2.1 (14)", device: "iPad (iPad16,3)", system: "iPadOS 26.1")
        let query = try #require(url.query(percentEncoded: true))
        #expect(!query.contains(" "))
        #expect(queryItems(of: url)["device"] == "iPad (iPad16,3) on iPadOS 26.1")
    }
}
