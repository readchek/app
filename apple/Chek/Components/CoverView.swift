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
                            .transition(.opacity)
                    } else {
                        CoverPlaceholder(title: title)
                    }
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
                .overlay {
                    // A hairline keeps white covers from melting into the page.
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
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

/// A plain cover with the title set small at the top, toned from the title
/// so the same book always looks the same, and quiet enough to sit among
/// real covers.
private struct CoverPlaceholder: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hue = Double(abs(title.hashValueStable) % 360) / 360
        ZStack(alignment: .topLeading) {
            Color(hue: hue, saturation: 0.12, brightness: colorScheme == .dark ? 0.26 : 0.9)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(4)
                .padding(10)
        }
    }
}

private extension String {
    /// A hash that's the same on every launch, unlike `hashValue`.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}
