import Foundation
import Testing
@testable import Chek

/// How far along a publication reads as, from what's stored about it.
struct ReadingStatusTests {
    @Test func finishedWinsOverProgress() {
        #expect(ReadingStatus(progress: 0.4, finished: true, opened: true) == .finished)
    }

    @Test func progressIsCappedAtOne() {
        #expect(ReadingStatus(progress: 1.7, finished: false, opened: true) == .inProgress(1))
    }

    @Test func openedWithoutProgressIsStarted() {
        #expect(ReadingStatus(progress: 0, finished: false, opened: true) == .started)
        #expect(ReadingStatus(progress: nil, finished: false, opened: true) == .started)
    }

    @Test func untouchedIsNew() {
        #expect(ReadingStatus(progress: nil, finished: false, opened: false) == .new)
        #expect(ReadingStatus.new.progress == nil)
    }

    @Test func progressRoundTrips() {
        #expect(ReadingStatus.inProgress(0.25).progress == 0.25)
        #expect(ReadingStatus.finished.progress == 1)
        #expect(ReadingStatus.started.progress == 0)
    }
}
