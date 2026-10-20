import Foundation
import Testing
@testable import Chek

/// The server's extension routes decode as the contract describes them,
/// nulls and all.
struct SourceAPITests {
    @Test func chaptersDecodeWithNulls() throws {
        let json = Data("""
        {"items":[{"id":"c1","title":"Chapter 1","number":null,"version":null,"published":null}]}
        """.utf8)
        let items = try JSONDecoder().decode(ChekAPI.Items<ChekAPI.SourceChapter>.self, from: json).items
        #expect(items.count == 1)
        #expect(items[0].number == nil)
        #expect(items[0].displayTitle == "Chapter 1")
    }

    @Test func installedExtensionsDecode() throws {
        let json = Data("""
        {"id":"page.chek.mangadex","name":"MangaDex","version":"0.1.0","repositoryId":1,"sites":["api.mangadex.org"],"languages":["en"],"installedAt":"2026-10-20T00:00:00Z","usable":true,"update":null}
        """.utf8)
        let item = try JSONDecoder().decode(ChekAPI.InstalledExtension.self, from: json)
        #expect(item.name == "MangaDex")
        #expect(item.usable)
        #expect(item.update == nil)
    }

    @Test func seriesSnapshotsRoundTrip() throws {
        let series = ChekAPI.SourceSeries(id: "s", title: "T", summary: nil, coverUrl: "/api/x", contributors: [.init(name: "A", role: "author")], readingDirection: "rtl")
        let data = try JSONEncoder().encode(series)
        #expect(try JSONDecoder().decode(ChekAPI.SourceSeries.self, from: data) == series)
    }
}
