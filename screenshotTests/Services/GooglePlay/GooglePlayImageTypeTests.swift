#if DEBUG
import Testing
import CoreGraphics
@testable import Screenshot_Bro

struct GooglePlayImageTypeTests {
    @Test func acceptsWithinEdgeBounds() {
        #expect(GPImageType.accepts(width: 320, height: 320))
        #expect(GPImageType.accepts(width: 3840, height: 3840))
        #expect(!GPImageType.accepts(width: 319, height: 800))
        #expect(!GPImageType.accepts(width: 3841, height: 3840))
    }

    @Test func rejectsAspectRatioWiderThanTwoToOne() {
        #expect(GPImageType.accepts(width: 1000, height: 2000))
        #expect(!GPImageType.accepts(width: 1000, height: 2001))
        // Orientation-independent.
        #expect(!GPImageType.accepts(width: 2001, height: 1000))
    }

    @Test func detectFavoursPhoneForTallScreens() {
        #expect(GPImageType.detect(width: 1242, height: 2688) == .phoneScreenshots)
    }

    @Test func detectFavoursTabletForSquarerScreens() {
        #expect(GPImageType.detect(width: 2048, height: 2732) == .tenInchScreenshots)
        #expect(GPImageType.detect(width: 1200, height: 1600) == .sevenInchScreenshots)
    }
}
#endif
