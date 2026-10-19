import ChekReader
import Foundation
import Observation
import UIKit

/// How text looks in the reader, the same for every book and kept between
/// launches. The reader applies ``preferences`` whenever they change.
@MainActor
@Observable
final class ReaderSettings {
    /// Line spacing choices, in place of a free slider, so every step looks
    /// deliberate.
    enum LineSpacing: String, CaseIterable, Identifiable {
        case original, compact, regular, relaxed

        var id: Self { self }

        var lineHeight: Double? {
            switch self {
            case .original: nil
            case .compact: 1.3
            case .regular: 1.55
            case .relaxed: 1.85
            }
        }
    }

    /// Margin choices, multiplying the reader's standard margins.
    enum Margins: String, CaseIterable, Identifiable {
        case narrow, regular, wide

        var id: Self { self }

        var scale: Double {
            switch self {
            case .narrow: 0.5
            case .regular: 1
            case .wide: 2
            }
        }
    }

    static let fontScaleStep = 0.1

    var theme: ReaderPreferences.Theme {
        didSet { store(theme.rawValue, for: .theme); update() }
    }
    var font: ReaderPreferences.Font {
        didSet { store(font.rawValue, for: .font); update() }
    }
    var fontScale: Double {
        didSet { store(fontScale, for: .fontScale); update() }
    }
    var lineSpacing: LineSpacing {
        didSet { store(lineSpacing.rawValue, for: .lineSpacing); update() }
    }
    var margins: Margins {
        didSet { store(margins.rawValue, for: .margins); update() }
    }
    var pageTransition: ReaderPreferences.PageTransition {
        didSet { store(pageTransition.rawValue, for: .pageTransition); update() }
    }
    var comicFlow: ReaderPreferences.ComicFlow {
        didSet { store(comicFlow.rawValue, for: .comicFlow); update() }
    }

    /// Everything above, as the reader takes it. Stored rather than computed
    /// so views that apply it observe one property.
    private(set) var preferences = ReaderPreferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme.rawValue).flatMap(ReaderPreferences.Theme.init(rawValue:)) ?? .original
        font = defaults.string(forKey: Key.font.rawValue).flatMap(ReaderPreferences.Font.init(rawValue:)) ?? .original
        let scale = defaults.double(forKey: Key.fontScale.rawValue)
        fontScale = scale > 0 ? scale : 1
        lineSpacing = defaults.string(forKey: Key.lineSpacing.rawValue).flatMap(LineSpacing.init(rawValue:)) ?? .original
        margins = defaults.string(forKey: Key.margins.rawValue).flatMap(Margins.init(rawValue:)) ?? .regular
        pageTransition = defaults.string(forKey: Key.pageTransition.rawValue).flatMap(ReaderPreferences.PageTransition.init(rawValue:)) ?? .curl
        comicFlow = defaults.string(forKey: Key.comicFlow.rawValue).flatMap(ReaderPreferences.ComicFlow.init(rawValue:)) ?? .automatic
        update()
    }

    var canMakeTextSmaller: Bool {
        fontScale - Self.fontScaleStep >= ReaderPreferences.fontScaleRange.lowerBound - 0.001
    }

    var canMakeTextLarger: Bool {
        fontScale + Self.fontScaleStep <= ReaderPreferences.fontScaleRange.upperBound + 0.001
    }

    func makeTextSmaller() {
        guard canMakeTextSmaller else { return }
        fontScale = ((fontScale - Self.fontScaleStep) * 10).rounded() / 10
    }

    func makeTextLarger() {
        guard canMakeTextLarger else { return }
        fontScale = ((fontScale + Self.fontScaleStep) * 10).rounded() / 10
    }

    func reset() {
        theme = .original
        font = .original
        fontScale = 1
        lineSpacing = .original
        margins = .regular
    }

    private func update() {
        preferences = ReaderPreferences(
            fontScale: fontScale * Self.deviceTextScale,
            theme: theme,
            font: font,
            lineHeight: lineSpacing.lineHeight,
            marginScale: margins.scale,
            pageTransition: pageTransition,
            comicFlow: comicFlow
        )
    }

    /// iPad is read from further away than iPhone, so the same size reads
    /// smaller there. Its text starts a step larger, as in Books, beneath
    /// the size you choose, which still shows as 100%.
    private static let deviceTextScale = UIDevice.current.userInterfaceIdiom == .pad ? 1.15 : 1

    private enum Key: String {
        case theme = "reader.theme"
        case font = "reader.font"
        case fontScale = "reader.fontScale"
        case lineSpacing = "reader.lineSpacing"
        case margins = "reader.margins"
        case pageTransition = "reader.pageTransition"
        case comicFlow = "reader.comicFlow"
    }

    private func store(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
