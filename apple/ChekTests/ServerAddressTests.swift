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
