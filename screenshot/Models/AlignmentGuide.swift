import Foundation

enum AlignmentAxis: Hashable {
    case horizontal // Y-aligned (horizontal line)
    case vertical   // X-aligned (vertical line)
}

struct AlignmentGuide: Identifiable, Equatable {
    var id: AlignmentAxis { axis }
    let axis: AlignmentAxis
    let position: CGFloat   // canvas coordinate of the line
    let start: CGFloat      // line extent start on perpendicular axis
    let end: CGFloat        // line extent end on perpendicular axis
}

struct SnapResult {
    let snappedOffset: CGSize  // adjusted drag offset in canvas coords
    let guides: [AlignmentGuide]
}
