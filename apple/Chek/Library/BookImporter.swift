import ChekReader
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// What an import found out about a book, ready to store as a ``Book``.
nonisolated struct ImportedBook: Sendable {
    var id: UUID
    var title: String
    var authors: String
    var formatName: String
    var kind: PublicationKind
    var seriesTitle: String?
    var seriesPosition: Double?
    var fileName: String
    var fileSize: Int64
    var hasCover: Bool
    /// Where to start reading, as Locator JSON, for a book carried over
    /// with a place already kept.
    var location: Data?
    var progress: Double?
}

/// Copies books into the library and reads their metadata and covers.
nonisolated enum BookImporter {
    /// The file types the library offers to import. The reader detects the
    /// real format from the file's bytes, so a ZIP is accepted too: comics
    /// and FictionBooks are often saved as plain `.zip` files.
    static let contentTypes: [UTType] = [
        .epub, .pdf, .plainText, .zip,
        UTType(importedAs: "net.daringfireball.markdown"),
        UTType(importedAs: "com.readchek.cbz"),
        UTType(importedAs: "com.readchek.cbt"),
        UTType(importedAs: "com.readchek.mobi"),
        UTType(importedAs: "com.readchek.azw3"),
        UTType(importedAs: "com.readchek.fb2"),
        UTType(importedAs: "com.readchek.fbz"),
    ]

    private static let coverPixelSize = 600

    /// Copies the file at `source` into a new folder in the library and
    /// opens it once to check it can be read.
    ///
    /// With `moving`, the file is moved instead, for files already on the
    /// device that would otherwise take their space twice. `page` is a
    /// zero-based page to start a comic or PDF at.
    ///
    /// Throws the reader's error when the file isn't a publication the
    /// reader can open, and leaves nothing behind in that case; a moved file
    /// goes back where it was.
    @concurrent
    static func importBook(from source: URL, moving: Bool = false, page: Int? = nil) async throws -> ImportedBook {
        let id = UUID()
        let folder = LibraryFiles.folder(for: id)
        let destination = folder.appending(path: source.lastPathComponent)

        // Files picked from other apps or providers are only readable while
        // their security scope is open.
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if moving {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            LibraryFiles.remove(id)
            throw error
        }

        do {
            let publication = try await Publication.open(.file(destination))
            let hasCover = await writeCover(of: publication, file: destination, to: LibraryFiles.coverURL(for: id))
            let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let start = page.flatMap { startLocator(in: publication, file: destination, page: $0) }
            return ImportedBook(
                id: id,
                title: displayTitle(publication.metadata.title, fileName: destination.deletingPathExtension().lastPathComponent),
                authors: publication.metadata.authors.map(\.name).formatted(.list(type: .and)),
                formatName: shortName(of: publication.format),
                kind: [.cbz, .cbt, .cbr, .cb7].contains(publication.format) ? .comic : .book,
                seriesTitle: publication.metadata.series?.name,
                seriesPosition: publication.metadata.series?.position,
                fileName: destination.lastPathComponent,
                fileSize: Int64(size ?? 0),
                hasCover: hasCover,
                location: start.flatMap { try? JSONEncoder().encode($0) },
                progress: start?.locations.totalProgression
            )
        } catch {
            if moving {
                try? FileManager.default.moveItem(at: destination, to: source)
            }
            LibraryFiles.remove(id)
            throw error
        }
    }

    /// A position at the start of zero-based `page`, as the comic and PDF
    /// navigators write them. Reflowable books have no fixed pages, so
    /// they start from the beginning.
    private static func startLocator(in publication: Publication, file: URL, page: Int) -> Locator? {
        guard page > 0 else { return nil }
        if publication.format == .pdf {
            guard let link = publication.readingOrder.first,
                  let count = PDFDocument(url: file)?.pageCount,
                  count > 0
            else { return nil }
            let index = min(page, count - 1)
            let progression = Double(index) / Double(count)
            return Locator(
                href: link.path,
                mediaType: "application/pdf",
                locations: Locator.Locations(fragments: ["page=\(index + 1)"], progression: progression, totalProgression: progression)
            )
        }
        let pages = publication.readingOrder
        guard pages.allSatisfy({ $0.mediaType?.hasPrefix("image/") == true }), !pages.isEmpty else { return nil }
        let index = min(page, pages.count - 1)
        guard var locator = publication.locator(for: pages[index]) else { return nil }
        locator.locations.progression = 0
        locator.locations.totalProgression = Double(index) / Double(pages.count)
        return locator
    }

    /// The publication's title, or one made from its file name when it has
    /// none or only repeats the file name, as comic archives often do.
    static func displayTitle(_ title: String?, fileName: String) -> String {
        guard let title, !title.isEmpty, title != fileName else {
            return self.title(fromFileName: fileName)
        }
        return title
    }

    /// A short label for the format, such as "CBZ", that fits under a cover.
    static func shortName(of format: ReaderFormat) -> String {
        switch format {
        case .plainText: String(localized: "Text")
        case .markdown: "Markdown"
        case .fb2, .fb2Zip: "FB2"
        default: format.fileExtensions.first?.uppercased() ?? format.name
        }
    }

    /// A readable title from a file name such as `birds-eye_vol_01`, for
    /// publications that don't name themselves.
    static func title(fromFileName name: String) -> String {
        // Underscores always break words; a dot or hyphen does unless it
        // sits between digits, as in "3.0" or "1-2".
        let characters = Array(name)
        var spaced = ""
        for (index, character) in characters.enumerated() {
            let inNumber = index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
            let isBreak = character == "_" || ((character == "." || character == "-") && !inNumber)
            spaced.append(isBreak ? " " : character)
        }
        let words = spaced.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return name }
        // Keep words that already have capitals, such as "MURAI" or "iPad".
        return words.map { word in
            word.contains(where: \.isUppercase) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
    }

    /// Saves a thumbnail of the book's cover, falling back to the first
    /// page for comics and PDFs. Returns whether there was a cover.
    private static func writeCover(of publication: Publication, file: URL, to url: URL) async -> Bool {
        if publication.format == .pdf {
            guard let page = PDFDocument(url: file)?.page(at: 0),
                  let image = page.thumbnail(of: CGSize(width: coverPixelSize, height: coverPixelSize), for: .cropBox).cgImage
            else { return false }
            return write(image, to: url)
        }

        let firstImage = publication.readingOrder.first { $0.mediaType?.hasPrefix("image/") == true }
        guard let link = publication.cover ?? firstImage,
              let data = try? await publication.data(at: link.href),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return false }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: coverPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        return write(image, to: url)
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
