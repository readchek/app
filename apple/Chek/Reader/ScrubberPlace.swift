import Foundation

/// What the reader says under its title about where you are.
///
/// Comics and PDFs have real page numbers. Text that reflows has positions
/// instead, which aren't pages you'd recognize, so it shows how far
/// through you are. Past the last page, on the chapter end, neither is
/// true any more: repeating "20 of 20" would say you're still on the last
/// page, so the label says the chapter is finished instead.
nonisolated enum ScrubberPlace: Equatable {
    case page(Int, of: Int)
    case progress(Double)
    case finished
    case none

    static func make(showsPages: Bool, position: Int, count: Int, progress: Double?, isAtChapterEnd: Bool) -> ScrubberPlace {
        if isAtChapterEnd {
            return .finished
        }
        if showsPages, count > 0 {
            return .page(position, of: count)
        }
        if let progress {
            return .progress(progress)
        }
        return .none
    }
}
