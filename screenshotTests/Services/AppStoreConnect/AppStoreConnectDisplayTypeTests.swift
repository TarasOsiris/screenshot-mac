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

    @Test func modernDisplayTypesUseSupportedAppStoreConnectValues() {
        #expect(ASCDisplayType.iphone69.appStoreConnectValue == "APP_IPHONE_67")
        #expect(ASCDisplayType.iphone63.appStoreConnectValue == "APP_IPHONE_61")
        #expect(ASCDisplayType.ipadPro129M4.appStoreConnectValue == "APP_IPAD_PRO_3GEN_129")
        #expect(ASCDisplayType.ipadPro11M4.appStoreConnectValue == "APP_IPAD_PRO_3GEN_11")
        #expect(ASCDisplayType.ipadPro129M4.accepts(width: 2064, height: 2752))
        #expect(ASCDisplayType.detect(width: 2064, height: 2752) == .ipadPro129M4)
    }

    @Test func platformGatingMatchesFamily() {
        #expect(ASCDisplayType.iphone67.accepts(platform: .ios))
        #expect(!ASCDisplayType.iphone67.accepts(platform: .macOS))
        #expect(ASCDisplayType.desktop.accepts(platform: .macOS))
        #expect(!ASCDisplayType.desktop.accepts(platform: .ios))
        #expect(ASCDisplayType.iphone67.accepts(platform: nil))
    }

    @Test func userSelectableCasesFilterByPlatform() {
        let ios = ASCDisplayType.userSelectableCases(forPlatform: .ios)
        #expect(ios.contains(.iphone67))
        #expect(ios.contains(.ipadPro129M4))
        #expect(!ios.contains(.desktop))

        let mac = ASCDisplayType.userSelectableCases(forPlatform: .macOS)
        #expect(mac == [.desktop])

        #expect(ASCDisplayType.userSelectableCases(forPlatform: nil) == ASCDisplayType.userSelectableCases)
    }
}
