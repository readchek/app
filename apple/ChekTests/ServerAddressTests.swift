import Foundation
import Testing
@testable import Chek

/// What people type as a server address, and what the app connects to.
struct ServerAddressTests {
    @Test func bareHostGetsHTTPS() {
        #expect(ServerStore.baseURL(from: "chek.example.com")?.absoluteString == "https://chek.example.com")
    }

    @Test func localAddressesGetHTTP() {
        #expect(ServerStore.baseURL(from: "192.168.1.5:8080")?.absoluteString == "http://192.168.1.5:8080")
        #expect(ServerStore.baseURL(from: "localhost:8787")?.absoluteString == "http://localhost:8787")
    }

    @Test func pathsStayAndQueriesGo() {
        #expect(ServerStore.baseURL(from: "https://example.com/chek/?x=1")?.absoluteString == "https://example.com/chek")
    }

    @Test func surroundingSpaceIsIgnored() {
        #expect(ServerStore.baseURL(from: "  chek.example.com \n")?.absoluteString == "https://chek.example.com")
    }

    @Test func nonsenseIsRefused() {
        #expect(ServerStore.baseURL(from: "") == nil)
        #expect(ServerStore.baseURL(from: "ftp://example.com") == nil)
        #expect(ServerStore.baseURL(from: "not a server") == nil)
    }
}

/// Who counts as someone else when signing in to a library already added.
struct ChangeUserTests {
    @Test func theSameIDIsTheSamePerson() {
        let user = ChekAPI.User(id: 7, name: "Robin")
        #expect(!ServerStore.isSomeoneElse(user, thanID: 7, named: "robin-old-name"))
    }

    @Test func anotherIDIsSomeoneElse() {
        let user = ChekAPI.User(id: 8, name: "Robin")
        #expect(ServerStore.isSomeoneElse(user, thanID: 7, named: "Robin"))
    }

    @Test func withoutAnIDTheNameDecides() {
        #expect(!ServerStore.isSomeoneElse(ChekAPI.User(id: 8, name: "Robin"), thanID: nil, named: "robin"))
        #expect(ServerStore.isSomeoneElse(ChekAPI.User(id: 8, name: "Sam"), thanID: nil, named: "Robin"))
    }
}
