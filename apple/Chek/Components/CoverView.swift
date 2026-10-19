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

/// A publication's cover at a fixed 2:3 shape, with a designed stand-in
/// while it loads or when there isn't one.
struct CoverView: View {
    let source: CoverSource
    let title: String
    var cornerRadius: CGFloat = 6

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
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
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
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
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200
                else { return nil }
                return await ImagePipeline.decode(data)
            }
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = loaded
        }
    }
}

/// A plain cover with the title set on it, colored from the title so the
/// same book always looks the same.
private struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        let hue = Double(abs(title.hashValueStable) % 360) / 360
        ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.35, brightness: 0.55), Color(hue: hue, saturation: 0.45, brightness: 0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(title)
                .font(.system(.headline, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .padding(12)
        }
    }
}

private extension String {
    /// A hash that's the same on every launch, unlike `hashValue`.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}
