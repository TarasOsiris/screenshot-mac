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

    /// The bar sizes each field to what it holds; the inspector shares one width across rows.
    func valueWidth(strip stripWidth: CGFloat) -> CGFloat {
        switch self {
        case .strip: stripWidth
        case .formRow: UIMetrics.InspectorRow.valueWidth
        }
    }
}

extension View {
    /// A form row must not outgrow the inspector — it wraps onto two lines when it does, which is
    /// what dropped Rotation below its label once its reset button appeared. Capping instead of
    /// fixing the width lets the slider give up points first; the bar has room, so it keeps its.
    @ViewBuilder
    func inspectorSliderWidth(_ layout: InspectorValueLayout, _ width: CGFloat = UIMetrics.SliderWidth.standard) -> some View {
        switch layout {
        case .strip: frame(width: width)
        case .formRow: frame(maxWidth: width)
        }
    }
}
