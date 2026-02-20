import SwiftUI

/// A view that captures a key combination when clicked.
/// Currently displays the bound hotkey; future versions can support custom recording.
struct HotkeyRecorderView: View {
    let label: String
    let currentBinding: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)

            Text(currentBinding)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .font(.system(.body, design: .monospaced))

            Spacer()
        }
    }
}
