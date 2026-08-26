@testable import Screenshot_Bro
import Testing

@MainActor
struct ProjectOpenProgressTests {

    @Test func startsIdleWithNothingToShow() {
        let progress = ProjectOpenProgress()
        #expect(progress.phase == .idle)
        #expect(!progress.isOpening)
        #expect(progress.showsEditorContent)
        #expect(progress.detail == nil)
        #expect(!progress.isLoadingImages)
    }

    @Test func beginEntersPreparingAndResetsImageCounters() {
        let progress = ProjectOpenProgress()
        progress.beginImages(total: 12)
        progress.advanceImages(to: 7)

        progress.begin(projectName: "My App", isRemote: false)

        #expect(progress.phase == .preparing)
        #expect(progress.isOpening)
        #expect(progress.imagesLoaded == 0)
        #expect(progress.imagesTotal == 0)
    }

    /// Exhaustive by construction: a new `Phase` joins this table automatically, and the two
    /// properties that gate the UI are asserted for every case in one place.
    ///
    /// The editor's rows must stay out of the view tree before `.building`, or the project-id
    /// change rebuilds the outgoing project's canvases before the overlay can paint.
    @Test(arguments: ProjectOpenProgress.Phase.allCases)
    func everyPhaseGatesContentAndSpeaksForItself(phase: ProjectOpenProgress.Phase) {
        let progress = ProjectOpenProgress()
        progress.begin(projectName: "My App", isRemote: false)
        progress.advance(to: phase)

        #expect(progress.isOpening == (phase != .idle))
        #expect(progress.showsEditorContent == (phase == .idle || phase == .building))
        #expect((progress.detail != nil) == (phase != .idle), "\(phase) needs a message")
    }

    @Test func advanceIsIgnoredOnceFinished() {
        let progress = ProjectOpenProgress()
        progress.begin(projectName: "My App", isRemote: false)
        progress.finish()

        progress.advance(to: .reading)

        #expect(progress.phase == .idle)
        #expect(!progress.isOpening)
    }

    @Test func remoteReadGetsTheICloudMessage() {
        let local = ProjectOpenProgress()
        local.begin(projectName: "My App", isRemote: false)
        local.advance(to: .reading)

        let remote = ProjectOpenProgress()
        remote.begin(projectName: "My App", isRemote: true)
        remote.advance(to: .reading)

        #expect(local.detail != remote.detail)
    }

    @Test func titleFallsBackToTheGenericStringWithoutAName() {
        let named = ProjectOpenProgress()
        named.begin(projectName: "My App", isRemote: false)

        let unnamed = ProjectOpenProgress()
        unnamed.begin(projectName: nil, isRemote: false)

        let blank = ProjectOpenProgress()
        blank.begin(projectName: "", isRemote: false)

        #expect(named.title != unnamed.title)
        #expect(blank.title == unnamed.title)
    }

    @Test func imageProgressClampsToTheAnnouncedTotal() {
        let progress = ProjectOpenProgress()
        progress.beginImages(total: 12)
        #expect(progress.isLoadingImages)

        progress.advanceImages(to: -5)
        #expect(progress.imagesLoaded == 0)

        progress.advanceImages(to: 99)
        #expect(progress.imagesLoaded == 12)
        // Fully loaded is not "loading" — the pill hides on its own.
        #expect(!progress.isLoadingImages)

        progress.finishImages()
        #expect(progress.imagesTotal == 0)
        #expect(!progress.isLoadingImages)
    }

    /// A handful of images decode faster than the eye can register, so the pill would only
    /// flash — the indicator is for waits worth explaining.
    @Test func tooFewImagesMeansNoIndicator() {
        let progress = ProjectOpenProgress()
        progress.beginImages(total: 0)
        #expect(!progress.isLoadingImages)

        progress.beginImages(total: 3)
        #expect(!progress.isLoadingImages)
    }
}
