import SwiftUI
import UIKit

/// A book's cover with its title, author and progress underneath.
struct BookCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCover(url: book.coverURL, title: book.title, formatName: book.formatName)
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !book.authors.isEmpty {
                Text(book.authors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let progress = book.progress {
                ProgressView(value: progress)
                    .accessibilityLabel(Text("Reading progress"))
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A cover thumbnail, or the title on a plain card when there's none.
private struct BookCover: View {
    let url: URL?
    let title: String
    let formatName: String
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.fill.tertiary)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                        Text(formatName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
            .task(id: url) {
                image = await Self.load(url)
            }
    }

    @concurrent
    private static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingForDisplay()
    }
}
