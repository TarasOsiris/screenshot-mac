import SwiftUI

/// Which surface a shared value control is drawing into: the dense bottom bar, an inspector form
/// row, where every row's field sits in one column and the unit suffixes in the next, or a property
/// popover's own label/slider/readout column.
///
/// The controls under `Properties/` are layouts of one editing layer (see `ShapeEditing`), so they
/// take this rather than each declaring its own `strip`/`form` pair.
enum InspectorValueLayout {
    case strip
    case formRow
    case popoverColumn

    var columnGap: CGFloat {
        switch self {
        case .strip: UIMetrics.InspectorRow.stripColumnGap
        case .formRow: UIMetrics.InspectorRow.columnGap
        case .popoverColumn: UIMetrics.PopoverRow.columnGap
        }
    }

    /// How far a bezeled `TextField`'s chrome sits inside the frame SwiftUI lays out for it, which
    /// the locale wash has to match. The inspector's grouped `Form` pads its rows' controls, so the
    /// bezel leaves the trailing and bottom edges bare; the bar's fields fill their frame, where the
    /// same inset gapped the wash along those two edges. UIKit's rounded border fills its frame
    /// either way, so iPad needs no inset.
    var fieldBezelInset: EdgeInsets {
        switch self {
        case .strip, .popoverColumn: EdgeInsets()
        case .formRow: UIMetrics.OverrideMark.formFieldBezelInset
        }
    }

    /// The bar sizes each field to what it holds; the inspector shares one width across rows, and a
    /// popover column keeps its own dense readout.
    func valueWidth(strip stripWidth: CGFloat) -> CGFloat {
        switch self {
        case .strip: stripWidth
        case .formRow: UIMetrics.InspectorRow.valueWidth
        case .popoverColumn: UIMetrics.PopoverRow.readoutWidth
        }
    }
}

extension View {
    /// A form row must not wrap: `LabeledContent` stacks the label *above* the content when the
    /// content doesn't fit the inspector's width. Capping instead of fixing the width lets the
    /// slider give up points first — the opacity row is the one that needs it. The bar and the
    /// popover columns have as much room as they want, so they keep the width.
    @ViewBuilder
    func inspectorSliderWidth(_ layout: InspectorValueLayout) -> some View {
        switch layout {
        case .strip, .popoverColumn: frame(width: UIMetrics.SliderWidth.standard)
        case .formRow: frame(maxWidth: UIMetrics.SliderWidth.standard)
        }
    }

    /// Places a unit suffix ("°", "%") in the inspector's unit column. Laid out plainly after the
    /// field, a suffix pushes that field left out of the shared column — which is what left
    /// Rotation short of Position and Size. The bar packs its units tight, so there it's a no-op.
    @ViewBuilder
    func inspectorUnitColumn(_ layout: InspectorValueLayout) -> some View {
        switch layout {
        case .strip, .popoverColumn: self
        case .formRow: frame(width: UIMetrics.InspectorRow.unitWidth, alignment: .leading)
        }
    }

    /// The other half of that column: a row with no unit reserves it, so its fields end on the
    /// same x as the rows that have one.
    @ViewBuilder
    func reservesInspectorUnitColumn(_ layout: InspectorValueLayout) -> some View {
        switch layout {
        case .strip, .popoverColumn: self
        case .formRow: padding(.trailing, UIMetrics.InspectorRow.unitWidth)
        }
    }

    /// A value field plus its unit, as one row. The suffix's styling and its column placement are
    /// one decision, so a new unit-bearing row can't get half of it.
    func unitSuffix(_ unit: String, _ layout: InspectorValueLayout) -> some View {
        HStack(spacing: 0) {
            self
            Text(verbatim: unit)
                .scaledFont(UIMetrics.FontSize.numericBadge)
                .foregroundStyle(.secondary)
                .inspectorUnitColumn(layout)
        }
    }
}
