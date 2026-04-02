import SwiftUI

struct ProjectListView: View {
    @ObservedObject var store: ProjectStore
    let onSelectProject: (Project) -> Void

    var body: some View {
        Text("Projects")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
