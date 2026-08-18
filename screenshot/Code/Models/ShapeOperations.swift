import Foundation

// Parameters for the canvas shape operations. They describe *what* was asked for, not any state,
// and the canvas menus name them directly — so nesting them in AppState made Views/Canvas/
// depend on App/ for four enums.

enum CenterAxis {
    case vertically, horizontally, both
}

enum DuplicateDirection {
    case all, left, right
}

enum ShapeAlignment: Equatable {
    case left, centerH, right, top, centerV, bottom
    case distributeH, distributeV
}

enum GeometryMatchMode { case position, size, both }
