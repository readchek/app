import SwiftUI
import UIKit

/// Where a cover image comes from.
enum CoverSource: Hashable {
    case none
    case file(URL)
    /// An image fetched with `request`, cached under `key`.
    case remote(key: String, request: URLRequest)

    var cacheKey: String? {
        switch self {
        case .none: nil
        case .file(let url): url.path(percentEncoded: false)
        case .remote(let key, _): key
        }
    }
}

/// A publication's cover filling a 2:3 frame, so grids line up, with a
/// quiet stand-in while it loads or when there isn't one.
struct CoverView: View {
    let source: CoverSource
    let title: String
    var cornerRadius: CGFloat = 6
    /// Off where the system frames the cover itself, as a long-press
    /// preview does, so no margin shows around it.
    var isFramed = true

    @State private var image: UIImage?
    /// Whether there's no picture to wait for: the publication has none,
    /// or it couldn't be loaded.
    @State private var isMissing = false

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            // Takes the frame's size, so the clip below crops
                            // a wider image to 2:3 instead of following it.
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .transition(.opacity)
                    } else if isMissing || source == .none {
                        CoverPlaceholder(title: title)
                    } else {
                        // Still loading: a plain fill, so a grid doesn't
                        // flash every title before its picture.
                        Rectangle()
                            .fill(.quaternary)
                    }
                }
                .clipShape(.rect(cornerRadius: isFramed ? cornerRadius : 0))
                .overlay {
                    // A hairline keeps white covers from melting into the page.
                    if isFramed {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(isFramed ? 0.18 : 0), radius: 4, y: 2)
            }
            .accessibilityHidden(true)
            .task(id: source) {
                await load()
            }
    }

    private func load() async {
        guard let key = source.cacheKey else {
            image = nil
            isMissing = true
            return
        }
        isMissing = false
        if let cached = ImagePipeline.shared.cachedImage(for: key) {
            image = cached
            return
        }
        let loaded: UIImage?
        switch source {
        case .none:
            loaded = nil
        case .file(let url):
            loaded = await ImagePipeline.shared.image(for: key) { await ImagePipeline.decodeFile(at: url) }
        case .remote(_, let request):
            loaded = await ImagePipeline.shared.image(for: key) {
                // The copy on disk first, so covers show offline and at once.
                if let data = ImagePipeline.diskData(for: key), let image = await ImagePipeline.decode(data) {
                    return image
                }
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200
                else { return nil }
                ImagePipeline.storeOnDisk(data, for: key)
                return await ImagePipeline.decode(data)
            }
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = loaded
            isMissing = loaded == nil
        }
    }
}

/// A plain cover for a publication without one: a book's mark and the
/// title set small on a neutral fill. Quiet enough to sit among real
/// covers, and plainly a book rather than a picture that didn't load.
private struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.fill.tertiary)
            // A small cover, as in a list row, has room for the mark alone.
            GeometryReader { proxy in
                Group {
                    if proxy.size.width < 70 {
                        Image(systemName: "book.closed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text(title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .padding(10)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
