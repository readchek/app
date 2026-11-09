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

    /// Everything above, as the reader takes it. Stored rather than computed
    /// so views that apply it observe one property.
    private(set) var preferences = ReaderPreferences()

    /// How a comic reads, where a reader has said so, by the series or
    /// publication it was said for. Sources and files often get it wrong,
    /// and the choice is about the series rather than how you read.
    private(set) var readingModes: [String: ReadingMode] = [:]

    /// Whether chapters show readers' comments from their sites, where a
    /// site has them. A reader can turn them off for every site at once.
    var showsComments: Bool {
        didSet { store(showsComments, for: .showsComments) }
    }

    /// Whose comments are hidden, by the extension they came through, so
    /// one site's name never hides someone else on another.
    private(set) var hiddenCommenters: [String: [String]] = [:]

    /// Each extension's name, for listing the hidden commenters by site
    /// when that site isn't open.
    private(set) var commentSites: [String: String] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme.rawValue).flatMap(ReaderPreferences.Theme.init(rawValue:)) ?? .original
        font = defaults.string(forKey: Key.font.rawValue).flatMap(ReaderPreferences.Font.init(rawValue:)) ?? .original
        let scale = defaults.double(forKey: Key.fontScale.rawValue)
        fontScale = scale > 0 ? scale : 1
        lineSpacing = defaults.string(forKey: Key.lineSpacing.rawValue).flatMap(LineSpacing.init(rawValue:)) ?? .original
        margins = defaults.string(forKey: Key.margins.rawValue).flatMap(Margins.init(rawValue:)) ?? .regular
        pageTransition = defaults.string(forKey: Key.pageTransition.rawValue).flatMap(ReaderPreferences.PageTransition.init(rawValue:)) ?? .slide
        // Directions chosen before reading modes still say how their
        // series read.
        let directions = defaults.dictionary(forKey: Key.readingDirections.rawValue) as? [String: String] ?? [:]
        var modes = directions.compactMapValues { direction -> ReadingMode? in
            switch direction {
            case Publication.ReadingProgression.rightToLeft.rawValue: .manga
            case Publication.ReadingProgression.leftToRight.rawValue: .comic
            default: nil
            }
        }
        let chosen = defaults.dictionary(forKey: Key.readingModes.rawValue) as? [String: String] ?? [:]
        modes.merge(chosen.compactMapValues(ReadingMode.init(rawValue:))) { _, chosen in chosen }
        readingModes = modes
        showsComments = defaults.object(forKey: Key.showsComments.rawValue) as? Bool ?? true
        hiddenCommenters = defaults.dictionary(forKey: Key.hiddenCommenters.rawValue) as? [String: [String]] ?? [:]
        commentSites = defaults.dictionary(forKey: Key.commentSites.rawValue) as? [String: String] ?? [:]
        update()
    }

    /// The preferences for reading what `settingsKey` names: the ones
    /// above, laid out the way chosen for it. Left on automatic, a series
    /// its source calls a vertical strip scrolls, and anything else is
    /// left to the reader to tell from its pages.
    func preferences(for settingsKey: String) -> ReaderPreferences {
        var preferences = preferences
        switch readingMode(for: settingsKey) {
        case .automatic:
            preferences.comicFlow = StripSeries.contains(settingsKey, in: defaults) ? .scrolled : .automatic
        case .comic:
            preferences.comicFlow = .paged
            preferences.readingProgression = .leftToRight
        case .manga:
            preferences.comicFlow = .paged
            preferences.readingProgression = .rightToLeft
        case .webtoon:
            preferences.comicFlow = .scrolled
        }
        return preferences
    }

    /// How what `settingsKey` names reads: what was chosen for it, or
    /// automatic.
    func readingMode(for settingsKey: String) -> ReadingMode {
        readingModes[settingsKey] ?? .automatic
    }

    func setReadingMode(_ mode: ReadingMode, for settingsKey: String) {
        readingModes[settingsKey] = mode == .automatic ? nil : mode
        store(readingModes.mapValues(\.rawValue), for: .readingModes)
        // The old record would bring a direction back after choosing automatic.
        var directions = defaults.dictionary(forKey: Key.readingDirections.rawValue) as? [String: String] ?? [:]
        if directions.removeValue(forKey: settingsKey) != nil {
            store(directions, for: .readingDirections)
        }
    }

    /// Whether `name`'s comments from `site`, an extension's id, are hidden.
    func isHidden(_ name: String, on site: String) -> Bool {
        hiddenCommenters[site]?.contains(name) ?? false
    }

    /// Hides or shows again everything `name` writes on `site`, an
    /// extension's id, named `siteName` for the list of hidden commenters.
    func setHidden(_ isHidden: Bool, _ name: String, on site: String, siteName: String? = nil) {
        var names = hiddenCommenters[site] ?? []
        names.removeAll { $0 == name }
        if isHidden {
            names.append(name)
        }
        hiddenCommenters[site] = names.isEmpty ? nil : names
        if let siteName {
            commentSites[site] = siteName
        }
        store(hiddenCommenters, for: .hiddenCommenters)
        store(commentSites, for: .commentSites)
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
            pageTransition: pageTransition
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
        case readingDirections = "reader.readingDirections"
        case readingModes = "reader.readingModes"
        case showsComments = "reader.showsComments"
        case hiddenCommenters = "reader.hiddenCommenters"
        case commentSites = "reader.commentSites"
    }

    private func store(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}

/// How a comic's pages follow one another, chosen once for a series.
///
/// One choice in place of a layout and a direction, since the two go
/// together: a webtoon scrolls down, manga turns right to left and other
/// comics turn left to right.
nonisolated enum ReadingMode: String, CaseIterable, Identifiable, Sendable {
    /// What the file or site says, and failing that, what the pages look like.
    case automatic
    /// Pages turned left to right.
    case comic
    /// Pages turned right to left.
    case manga
    /// One column scrolled down.
    case webtoon

    var id: Self { self }
}

/// The series their sources call vertical strips, kept on the device so
/// a chapter opens scrolling at once instead of being looked at first.
/// The newest are kept, since a reader only goes back to so many series.
nonisolated enum StripSeries {
    private static let key = "reader.stripSeries"
    private static let kept = 500

    static func contains(_ settingsKey: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.stringArray(forKey: key)?.contains(settingsKey) ?? false
    }

    /// Notes whether the series `settingsKey` names is a strip.
    static func note(_ isStrip: Bool, for settingsKey: String, in defaults: UserDefaults = .standard) {
        var series = defaults.stringArray(forKey: key) ?? []
        guard series.contains(settingsKey) != isStrip else { return }
        series.removeAll { $0 == settingsKey }
        if isStrip {
            series.append(settingsKey)
        }
        defaults.set(Array(series.suffix(kept)), forKey: key)
    }
}

extension SourceChapterRef {
    /// Where reading settings for a source's series are kept.
    nonisolated static func settingsKey(server: UUID, source: String, series: String) -> String {
        "source/\(server.uuidString)/\(source)/\(series)"
    }
}
