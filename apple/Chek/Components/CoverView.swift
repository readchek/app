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
                    } else {
                        CoverPlaceholder(title: title)
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
            return
        }
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
        }
    }
}

/// A plain cover with the title set small on a neutral fill: quiet enough
/// to sit among real covers, and never mistaken for one.
private struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(10)
        }
    }
}
