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
    var fileName: String
    var hasCover: Bool
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
    /// Throws the reader's error when the file isn't a publication the
    /// reader can open, and leaves nothing behind in that case.
    @concurrent
    static func importBook(from source: URL) async throws -> ImportedBook {
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
            try FileManager.default.copyItem(at: source, to: destination)

            let publication = try await Publication.open(.file(destination))
            let hasCover = await writeCover(of: publication, file: destination, to: LibraryFiles.coverURL(for: id))
            return ImportedBook(
                id: id,
                title: publication.metadata.title ?? destination.deletingPathExtension().lastPathComponent,
                authors: publication.metadata.authors.map(\.name).formatted(.list(type: .and)),
                formatName: publication.format.name,
                fileName: destination.lastPathComponent,
                hasCover: hasCover
            )
        } catch {
            LibraryFiles.remove(id)
            throw error
        }
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
