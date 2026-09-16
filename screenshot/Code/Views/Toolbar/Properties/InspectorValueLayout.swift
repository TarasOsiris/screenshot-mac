import SwiftUI

/// Which surface a shared value control is drawing into: the dense bottom bar, or an inspector
/// form row, where every row's field sits in one column and the unit suffixes in the next.
///
/// The controls under `Properties/` are two layouts of one editing layer (see `ShapeEditing`), so
/// they take this rather than each declaring its own `strip`/`form` pair.
enum InspectorValueLayout {
    case strip
    case formRow

    /// Between the two columns of a value area (X↔Y, slider↔field).
    var columnGap: CGFloat {
        switch self {
        case .strip: 4
        case .formRow: UIMetrics.InspectorRow.columnGap
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
