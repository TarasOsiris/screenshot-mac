import Foundation
@testable import Screenshot_Bro
import Testing

/// Item-provider callbacks build these off the main queue (SCREENSHOT-BRO-2B).
nonisolated struct DropFailureTests {

    private static let error = NSError(
        domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]
    )

    @Test func factoriesBuildOffTheMainActor() async {
        let failures = await Task.detached {
            [
                DropFailure.image(Self.error),
                DropFailure.imageOrSvg(Self.error),
                DropFailure.svg(Self.error),
                DropFailure.image(nil),
                DropFailure.unrenderableSvg,
            ]
        }.value

        for failure in failures {
            #expect(!failure.title.isEmpty)
            #expect(!failure.message.isEmpty)
        }
        for failure in failures.prefix(3) {
            #expect(failure.message.contains("boom"))
        }
    }
}
