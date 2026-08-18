import Foundation
@testable import Screenshot_Bro
import Testing

// Step transitions used to be spread across a SwiftUI view's `@State` and an `#if os(iOS)`
// `.onChange(of: path)`, so none of it could be tested and half of it was invisible to the macOS
// test run entirely. These run against ASCUploadFlowModel with no view.
@MainActor
struct ASCUploadFlowNavigationTests {

    private func makeModel() -> ASCUploadFlowModel {
        ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
    }

    @Test func advanceSetsTheStepThenNotifiesNavigation() {
        let model = makeModel()
        var pushed: [ASCUploadStep] = []
        // The closure must see the new step: iPad pushes onto its path from here.
        model.navigationDidAdvance = { [weak model] step in
            #expect(model?.step == step)
            pushed.append(step)
        }

        model.advance(to: .pickingVersion)
        model.advance(to: .configuringPlan)

        #expect(model.step == .configuringPlan)
        #expect(pushed == [.pickingVersion, .configuringPlan])
    }

    @Test func retreatNotifiesSoTheTerminalScreenCanPop() {
        let model = makeModel()
        var retreats = 0
        model.navigationWillRetreat = { retreats += 1 }

        model.advance(to: .uploading)
        model.retreatAfterScreenshotSync(to: .configuringPlan)

        #expect(model.step == .configuringPlan)
        #expect(retreats == 1)
    }

    /// The done screen flips the already-pushed .uploading screen's content; pushing again would
    /// stack a duplicate on iPad.
    @Test func completingTheTerminalStepDoesNotPush() {
        let model = makeModel()
        var pushes = 0
        model.navigationDidAdvance = { _ in pushes += 1 }

        model.advance(to: .uploading)
        model.completeTerminalStep(.done)

        #expect(model.step == .done)
        #expect(pushes == 1, "only the .uploading push")
    }

    @Test func goBackWalksTheStepChain() {
        let model = makeModel()
        let chain: [(from: ASCUploadStep, to: ASCUploadStep)] = [
            (.configuringPlan, .editingMetadata),
            (.editingMetadata, .pickingVersion),
            (.pickingVersion, .pickingApp),
        ]
        for hop in chain {
            model.advance(to: hop.from)
            model.goBack()
            #expect(model.step == hop.to)
        }
    }

    @Test func goBackClearsBothErrorFields() {
        let model = makeModel()
        model.advance(to: .pickingVersion)
        model.errorMessage = "boom"
        model.errorDetailsText = "boom, in detail"

        model.goBack()

        #expect(model.errorMessage == nil)
        #expect(model.errorDetailsText == nil)
    }

    /// Leaving the review screen has to release the sync plan, which owns a temp folder of
    /// rendered screenshots.
    @Test func goBackFromReviewDiscardsTheSyncPlan() {
        let model = makeModel()
        model.advance(to: .reviewingChanges)
        model.goBack()

        #expect(model.step == .configuringPlan)
        #expect(model.screenshotSync.plan == nil)
    }

    // MARK: - iPad path (previously unreachable on macOS)

    @Test func aUserPopClearsTheError() {
        let model = makeModel()
        model.errorMessage = "stale"
        model.errorDetailsText = "stale detail"

        model.handlePathChange(from: [.pickingVersion, .editingMetadata], to: [.pickingVersion])

        #expect(model.step == .pickingVersion)
        #expect(model.errorMessage == nil)
        #expect(model.errorDetailsText == nil)
    }

    /// An upload failure pops .uploading *after* setting the message — that one is the result the
    /// user came back to read, so it must survive.
    @Test func poppingTheTerminalScreenKeepsTheError() {
        for terminal in [ASCUploadStep.uploading, .done] {
            let model = makeModel()
            model.errorMessage = "upload failed"
            model.errorDetailsText = "HTTP 409"

            model.handlePathChange(from: [.configuringPlan, terminal], to: [.configuringPlan])

            #expect(model.step == .configuringPlan)
            #expect(model.errorMessage == "upload failed", "popping \(terminal) must keep the error")
            #expect(model.errorDetailsText == "HTTP 409")
        }
    }

    /// A push is not a pop: pushing must not clear an error the destination is about to show.
    @Test func aPushOnlyUpdatesTheStep() {
        let model = makeModel()
        model.errorMessage = "keep me"

        model.handlePathChange(from: [.pickingVersion], to: [.pickingVersion, .editingMetadata])

        #expect(model.step == .editingMetadata)
        #expect(model.errorMessage == "keep me")
    }

    @Test func poppingToTheRootReturnsToPickingApp() {
        let model = makeModel()
        model.handlePathChange(from: [.pickingVersion], to: [])
        #expect(model.step == .pickingApp)
    }

    @Test func poppingAwayFromReviewDiscardsTheSyncPlan() {
        let model = makeModel()
        model.handlePathChange(from: [.configuringPlan, .reviewingChanges], to: [.configuringPlan])
        #expect(model.screenshotSync.plan == nil)
    }

    /// tearDown is the view's `.onDisappear`: without the discard, the rendered screenshots in the
    /// sync plan's temp folder leak.
    @Test func tearDownCancelsTheTaskAndReleasesThePlan() {
        let model = makeModel()
        model.uploadTask = Task {}
        model.tearDown()
        #expect(model.uploadTask == nil)
        #expect(model.screenshotSync.plan == nil)
    }
}
