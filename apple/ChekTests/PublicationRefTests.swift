import Foundation
import Testing
@testable import Chek

/// The one way a publication is named everywhere in the app.
struct PublicationRefTests {
    private let server = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func storageKeysTellKindsApart() {
        #expect(PublicationRef.server(server, 7).storageKey == "server/11111111-2222-3333-4444-555555555555/7")
        #expect(PublicationRef.source(server, "page.chek.mangadex", "abc").storageKey == "source/11111111-2222-3333-4444-555555555555/page.chek.mangadex/abc")
        #expect(PublicationRef.local(server).storageKey.hasPrefix("local/"))
    }

    @Test func serverIsKnownForServerPublications() {
        #expect(PublicationRef.server(server, 7).server == server)
        #expect(PublicationRef.source(server, "s", "c").server == server)
        #expect(PublicationRef.local(server).server == nil)
    }

    @Test func refsRoundTripThroughJSON() throws {
        let ref = PublicationRef.source(server, "s", "c")
        let data = try JSONEncoder().encode(ref)
        #expect(try JSONDecoder().decode(PublicationRef.self, from: data) == ref)
    }
}
