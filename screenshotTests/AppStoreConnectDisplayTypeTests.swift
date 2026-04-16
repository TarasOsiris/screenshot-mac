import Testing
@testable import Screenshot_Bro

struct AppStoreConnectDisplayTypeTests {
    @Test func desktopAcceptsLandscapeOnly() {
        #expect(ASCDisplayType.desktop.accepts(width: 2880, height: 1800))
        #expect(!ASCDisplayType.desktop.accepts(width: 1800, height: 2880))
        #expect(ASCDisplayType.detect(width: 1800, height: 2880) == nil)
    }

    @Test func phoneDisplayTypesAcceptBothOrientations() {
        #expect(ASCDisplayType.iphone69.accepts(width: 1320, height: 2868))
        #expect(ASCDisplayType.iphone69.accepts(width: 2868, height: 1320))
    }
}
