import SwiftUI

/// Substitutes the value a properties-bar slider is composing for the document's shape, so a
/// ~30 Hz drag re-evaluates one shape instead of the row that contains it.
///
/// The session read has to happen *here* rather than in `EditorRowView`'s body: reading it up
/// there would put the per-tick value in the row's tracking scope and rebuild every shape across
/// every template on each tick, which is the cost this exists to remove. `LiveShapeEditSession`
/// gates on the edited shape's id, so a shape that isn't being edited observes only the two
/// transitions that bracket the burst.
///
/// Editor-only by construction — the export and preview paths never build one, so a value that
/// has not reached `AppState.rows` can never reach exported bytes.
struct LiveShapeContent<Content: View>: View {
    let baseShape: CanvasShapeModel
    let session: LiveShapeEditSession
    @ViewBuilder let content: (CanvasShapeModel) -> Content

    var body: some View {
        content(session.liveShape(for: baseShape.id) ?? baseShape)
            .environment(\.isLiveShapeEdit, session.shapeId == baseShape.id)
    }
}

/// True while the shape being rendered carries an in-flight continuous edit rather than a
/// document value. Scoped to that one shape's subtree by `LiveShapeContent`, and never set on
/// the export/preview path — where the value is settled by definition. Defaults to false.
extension EnvironmentValues {
    @Entry var isLiveShapeEdit = false
}
