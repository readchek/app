import Foundation
import Testing
@testable import Chek

/// The server's extension routes decode as the contract describes them,
/// nulls and all.
struct SourceAPITests {
    @Test func chaptersDecodeWithNulls() throws {
        let json = Data("""
        {"items":[{"id":"c1","title":"Chapter 1","number":null,"version":null,"published":null}],"offset":0,"total":1}
        """.utf8)
        let page = try JSONDecoder().decode(ChekAPI.SourceChapterPage.self, from: json)
        let items = page.items
        #expect(page.total == 1)
        #expect(items.count == 1)
        #expect(items[0].number == nil)
        #expect(items[0].displayTitle == "Chapter 1")
    }

    /// A page's chapters know where they stand in reading order from
    /// either end, which is what keeps pages in order once kept.
    @Test func chapterPagesPlaceChaptersInReadingOrder() {
        let chapters = (1...3).map { ChekAPI.SourceChapter(id: "c\($0)", title: "") }
        let oldest = ChekAPI.SourceChapterPage(items: chapters, offset: 10, total: 50)
        #expect(oldest.known(.oldestFirst).map(\.position) == [11, 12, 13])
        let newest = ChekAPI.SourceChapterPage(items: chapters, offset: 10, total: 50)
        #expect(newest.known(.newestFirst).map(\.position) == [40, 39, 38])
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

    @Test func repositoriesDecodeWithAndWithoutCredentials() throws {
        let json = Data("""
        {"items":[
          {"id":1,"url":"https://chek.page/extensions/index.json","name":"Chek","allowListed":true,"usable":true,"hasCredentials":false,"extensionCount":2,"fetchedAt":null,"fetchError":null,"createdAt":"2026-10-20T00:00:00Z"},
          {"id":2,"url":"https://example.org/index.json","name":null,"allowListed":false,"usable":true,"extensionCount":0,"fetchedAt":null,"fetchError":null,"createdAt":"2026-10-20T00:00:00Z"}
        ]}
        """.utf8)
        let items = try JSONDecoder().decode(ChekAPI.Items<ChekAPI.ExtensionRepository>.self, from: json).items
        #expect(items[0].hasCredentials == false)
        #expect(items[1].hasCredentials == nil)
        #expect(items[1].displayName == "example.org")
    }

    @Test func credentialsEncodeAsTheServerReadsThem() throws {
        func object(_ credentials: ChekAPI.RepositoryCredentials) throws -> [String: String] {
            try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(credentials))
        }
        #expect(try object(.bearer(token: "t")) == ["type": "bearer", "token": "t"])
        #expect(try object(.basic(username: "u", password: "p")) == ["type": "basic", "username": "u", "password": "p"])
        #expect(try object(.header(name: "X-Api-Key", value: "v")) == ["type": "header", "name": "X-Api-Key", "value": "v"])
    }

    @Test func signInTrimsPastedTokensButNotPasswords() {
        var signIn = RepositorySignIn(kind: .token, token: "  ghp_abc\n")
        #expect(signIn.isComplete)
        #expect(signIn.credentials == .bearer(token: "ghp_abc"))

        signIn.kind = .password
        signIn.username = " reader "
        signIn.password = " secret "
        #expect(signIn.credentials == .basic(username: "reader", password: " secret "))
    }

    @Test func signInNeedsEveryFieldItsKindUses() {
        #expect(RepositorySignIn().isComplete)
        #expect(RepositorySignIn().credentials == nil)
        #expect(!RepositorySignIn(kind: .token, token: "  ").isComplete)
        #expect(!RepositorySignIn(kind: .password, password: "p").isComplete)
        #expect(!RepositorySignIn(kind: .header, headers: [.init(name: "X-Key")]).isComplete)
        #expect(RepositorySignIn(kind: .header, headers: [.init(name: "X-Key", value: "v")]).isComplete)
        #expect(!RepositorySignIn(kind: .header, headers: []).isComplete)
        #expect(!RepositorySignIn(kind: .header, headers: [.init(name: "A", value: "v"), .init(value: "w")]).isComplete)
    }

    @Test func oneHeaderIsSentAsHeaderAndSeveralAsHeaders() throws {
        let one = RepositorySignIn(kind: .header, headers: [.init(name: " X-Key ", value: "v")])
        #expect(one.credentials == .header(name: "X-Key", value: "v"))

        let access = RepositorySignIn(kind: .header, headers: [
            .init(name: "CF-Access-Client-Id", value: "id"),
            .init(name: "CF-Access-Client-Secret", value: "secret"),
        ])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(access.credentials)) as? [String: Any]
        #expect(json?["type"] as? String == "headers")
        let headers = json?["headers"] as? [[String: String]]
        #expect(headers == [["name": "CF-Access-Client-Id", "value": "id"], ["name": "CF-Access-Client-Secret", "value": "secret"]])
    }

    @MainActor @Test func repositoryFailuresAskForTheSignInTheyNeed() {
        #expect(ExtensionsModel.repositoryFailure(.server(status: 422, code: "repository_needs_token")).asks == .token)
        #expect(ExtensionsModel.repositoryFailure(.server(status: 422, code: "repository_needs_password")).asks == .password)
        #expect(ExtensionsModel.repositoryFailure(.server(status: 422, code: "repository_needs_credentials")).asks == .header)
        #expect(ExtensionsModel.repositoryFailure(.server(status: 422, code: "repository_credentials_refused")).asks == nil)
        #expect(ExtensionsModel.repositoryFailure(.server(status: 409, code: "repository_exists")).asks == nil)
    }

    @Test func githubRepositoriesAreNamedByOwnerAndRepo() throws {
        let json = Data(#"{"id":3,"url":"https://raw.githubusercontent.com/arya/sources/HEAD/index.json","name":null,"allowListed":false,"usable":true,"extensionCount":1}"#.utf8)
        let repository = try JSONDecoder().decode(ChekAPI.ExtensionRepository.self, from: json)
        #expect(repository.displayName == "arya/sources")
    }

    @Test func usersDecodeTheirRole() throws {
        let admin = try JSONDecoder().decode(ChekAPI.User.self, from: Data(#"{"id":1,"name":"a","role":"admin","libraryIds":[],"createdAt":"2026-10-20T00:00:00Z"}"#.utf8))
        #expect(admin.isAdmin)
        let reader = try JSONDecoder().decode(ChekAPI.User.self, from: Data(#"{"id":2,"name":"r","role":"reader"}"#.utf8))
        #expect(!reader.isAdmin)
    }

    @Test func seriesSnapshotsRoundTrip() throws {
        let series = ChekAPI.SourceSeries(id: "s", title: "T", summary: nil, coverUrl: "/api/x", contributors: [.init(name: "A", role: "author")], readingDirection: "rtl")
        let data = try JSONEncoder().encode(series)
        #expect(try JSONDecoder().decode(ChekAPI.SourceSeries.self, from: data) == series)
    }
}
