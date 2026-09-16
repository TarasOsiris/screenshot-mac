import SwiftUI

/// Which surface a shared value control is drawing into: the dense bottom bar, or an inspector
/// form row, where every row's field sits in one column and the unit suffixes in the next.
///
/// The controls under `Properties/` are two layouts of one editing layer (see `ShapeEditing`), so
/// they take this rather than each declaring its own `strip`/`form` pair.
enum InspectorValueLayout {
    case strip
    case formRow

    var columnGap: CGFloat {
        switch self {
        case .strip: 4
        case .formRow: UIMetrics.InspectorRow.columnGap
        }
    }

    /// How far a bezeled `TextField`'s chrome sits inside the frame SwiftUI lays out for it, which
    /// the locale wash has to match. The inspector's grouped `Form` pads its rows' controls, so the
    /// bezel leaves the trailing and bottom edges bare; the bar's fields fill their frame, where the
    /// same inset gapped the wash along those two edges. UIKit's rounded border fills its frame
    /// either way, so iPad needs no inset.
    var fieldBezelInset: EdgeInsets {
        switch self {
        case .strip: EdgeInsets()
        case .formRow: UIMetrics.OverrideMark.formFieldBezelInset
        }
    }

    /// The bar sizes each field to what it holds; the inspector shares one width across rows.
    func valueWidth(strip stripWidth: CGFloat) -> CGFloat {
        switch self {
        case .strip: stripWidth
        case .formRow: UIMetrics.InspectorRow.valueWidth
        }
    }
}

extension View {
    /// A form row must not wrap: `LabeledContent` stacks the label *above* the content when the
    /// content doesn't fit the inspector's width, which is what dropped Rotation onto a second
    /// line as soon as its reset button appeared. Capping instead of fixing the width lets the
    /// slider give up points first. The bar has as much room as it wants, so it keeps the width.
    @ViewBuilder
    func inspectorSliderWidth(_ layout: InspectorValueLayout, _ width: CGFloat = UIMetrics.SliderWidth.standard) -> some View {
        switch layout {
        case .strip: frame(width: width)
        case .formRow: frame(maxWidth: width)
        }
    }

    /// Places a unit suffix ("°", "%") in the inspector's unit column. Laid out plainly after the
    /// field, a suffix pushes that field left out of the shared column — which is what left
    /// Rotation short of Position and Size. The bar packs its units tight, so there it's a no-op.
    @ViewBuilder
    func inspectorUnitColumn(_ layout: InspectorValueLayout) -> some View {
        switch layout {
        case .strip: self
        case .formRow: frame(width: UIMetrics.InspectorRow.unitWidth, alignment: .leading)
        }
    }

    /// The other half of that column: a row with no unit reserves it, so its fields end on the
    /// same x as the rows that have one.
    @ViewBuilder
    func reservesInspectorUnitColumn(_ layout: InspectorValueLayout) -> some View {
        switch layout {
        case .strip: self
        case .formRow: padding(.trailing, UIMetrics.InspectorRow.unitWidth)
        }
    }
}
