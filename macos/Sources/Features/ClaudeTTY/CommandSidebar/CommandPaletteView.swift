import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var store: CommandStore
    let isLocked: Bool
    let onSendCommand: (String) -> Void

    var body: some View {
        Text("Commands")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
