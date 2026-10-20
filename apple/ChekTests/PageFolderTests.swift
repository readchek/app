import Foundation
import Testing
@testable import Chek

/// The folders downloaded pages are kept in.
struct PageFolderTests {
    private struct Note: Codable, Equatable {
        var title: String
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ChekTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func pagesAndNoteRoundTrip() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = PageFolder(url: root.appending(path: "one"))
        try folder.prepare()
        try await folder.write(Data([1, 2, 3]), page: 0)
        try await folder.write(Data([4]), page: 1)
        #expect(folder.downloadedPageCount == nil)
        #expect(!folder.isComplete)
        try folder.markComplete(Note(title: "T"), pageCount: 2)
        #expect(folder.isComplete)
        #expect(folder.downloadedPageCount == 2)
        #expect(folder.readNote(Note.self) == Note(title: "T"))
        #expect(try Data(contentsOf: folder.page(1)) == Data([4]))
    }

    @Test func incompleteFoldersAreDroppedWhenListing() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let done = PageFolder(url: root.appending(path: "done"))
        try done.prepare()
        try done.markComplete(Note(title: "done"), pageCount: 0)
        let cutOff = PageFolder(url: root.appending(path: "cut-off"))
        try cutOff.prepare()
        try "x".write(to: root.appending(path: "stray.txt"), atomically: true, encoding: .utf8)

        let listed = PageFolder.completed(under: root)
        #expect(listed.map(\.url.lastPathComponent) == ["done"])
        #expect(!FileManager.default.fileExists(atPath: cutOff.url.path(percentEncoded: false)))
    }

    @Test func hexNamesAreSafeAndDistinct() {
        #expect(PageFolder.hex("a/b") == "612f62")
        #expect(PageFolder.hex("page.chek.mangadex") != PageFolder.hex("page.chek.mangadex2"))
    }
}
