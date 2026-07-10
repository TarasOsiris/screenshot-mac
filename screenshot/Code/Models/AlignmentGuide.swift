import Foundation

nonisolated enum AlignmentAxis: Hashable {
    case horizontal // Y-aligned (horizontal line)
    case vertical   // X-aligned (vertical line)
}

nonisolated struct AlignmentGuide: Identifiable, Equatable {
    var id: AlignmentAxis { axis }
    let axis: AlignmentAxis
    let position: CGFloat   // canvas coordinate of the line
    let start: CGFloat      // line extent start on perpendicular axis
    let end: CGFloat        // line extent end on perpendicular axis
}

nonisolated struct SnapResult {
    let snappedOffset: CGSize  // adjusted drag offset in canvas coords
    let guides: [AlignmentGuide]
}
