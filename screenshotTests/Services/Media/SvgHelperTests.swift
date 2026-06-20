import Testing
import Foundation
import SwiftUI
@testable import Screenshot_Bro

struct SvgHelperTests {

    @Test func applyColorReplacesDoubleQuotedFill() {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0\" fill=\"#FFB200\"/></svg>"
        let color = Color(red: 0, green: 0.56, blue: 0)
        let out = SvgHelper.applyColor(color, to: svg)
        #expect(out.contains("fill=\"\(color.hexString)\""))
        #expect(!out.contains("#FFB200"))
    }

    /// Regression: the indigo-noir bundled template (and projects created from it) stores SVG
    /// shapes with single-quoted attributes, e.g. `fill='#FFB200'`. The old regex only matched
    /// double quotes, so toggling "Override color" was a no-op for those shapes.
    @Test func applyColorReplacesSingleQuotedFill() {
        let svg = "<svg width='100' fill='none' xmlns='http://www.w3.org/2000/svg'><path d='M0 0' fill='#FFB200'/></svg>"
        let color = Color(red: 0, green: 0.56, blue: 0)
        let out = SvgHelper.applyColor(color, to: svg)
        #expect(out.contains("fill=\"\(color.hexString)\""))
        #expect(!out.contains("#FFB200"))
    }

    @Test func applyColorPreservesFillNone() {
        let svgDouble = "<svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\"><path d=\"M0 0\" fill=\"#FFB200\"/></svg>"
        let svgSingle = "<svg xmlns='http://www.w3.org/2000/svg' fill='none'><path d='M0 0' fill='#FFB200'/></svg>"
        let color = Color.red
        let outDouble = SvgHelper.applyColor(color, to: svgDouble)
        let outSingle = SvgHelper.applyColor(color, to: svgSingle)
        // The path's explicit colored fill should be replaced; the standalone fill="none" on the
        // root <svg> tag should be preserved so unfilled paths stay unfilled.
        #expect(outDouble.contains("fill=\"\(color.hexString)\""))
        #expect(outDouble.contains("fill=\"none\""))
        #expect(!outDouble.contains("#FFB200"))
        #expect(outSingle.contains("fill=\"\(color.hexString)\""))
        #expect(outSingle.contains("fill='none'"))
        #expect(!outSingle.contains("#FFB200"))
    }

    @Test func applyColorReplacesStrokeBothQuoteStyles() {
        let svg = "<svg xmlns='http://www.w3.org/2000/svg'><path stroke='#111111' fill='#222222'/><path stroke=\"#333333\" fill=\"#444444\"/></svg>"
        let out = SvgHelper.applyColor(Color.red, to: svg)
        #expect(!out.contains("#111111"))
        #expect(!out.contains("#222222"))
        #expect(!out.contains("#333333"))
        #expect(!out.contains("#444444"))
    }

    @Test func applyColorInjectsFillOnSvgTagWhenMissing() {
        let svg = "<svg xmlns='http://www.w3.org/2000/svg'><path d='M0 0'/></svg>"
        let color = Color.blue
        let out = SvgHelper.applyColor(color, to: svg)
        #expect(out.contains("<svg fill=\"\(color.hexString)\""))
    }
}
