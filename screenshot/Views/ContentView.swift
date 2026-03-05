import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(state: state)

            Divider()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(state.rows) { row in
                        EditorRowView(state: state, row: row)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
