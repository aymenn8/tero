import SwiftUI

struct ClipboardInfoRow: View {
    let label: String
    let value: String
    var shaded = false
    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).lineLimit(1).truncationMode(.middle).help(value)
        }.font(.system(size: 11)).padding(.horizontal, 8).frame(height: 25)
            .background(.white.opacity(shaded ? 0.035 : 0), in: .rect(cornerRadius: 5))
    }
}
