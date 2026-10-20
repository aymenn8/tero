import AppKit
import SwiftUI

struct ClipboardFilePreview: View {
    let entry: ClipboardEntry
    @State private var resolvedURL: URL?
    @State private var icons: [NSImage] = []

    var body: some View {
        Group {
            if (entry.files?.count ?? 0) > 1 {
                GeometryReader { geometry in
                    let side = min(160, geometry.size.height * 0.82, geometry.size.width * 0.65)
                    ZStack {
                        ForEach(Array(icons.enumerated().reversed()), id: \.offset) { index, icon in
                            Image(nsImage: icon)
                                .resizable().scaledToFit()
                                .frame(width: side, height: side)
                                .rotationEffect(.degrees(index == 0 ? 0 : -9))
                                .offset(x: index == 0 ? 5 : -9, y: index == 0 ? 5 : -6)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Group of \(entry.files?.count ?? 0) files")
            } else if let resolvedURL {
                ClipboardQuickLook(url: resolvedURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Text("Preview unavailable")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: entry.id) {
            resolvedURL = nil
            icons = []
            guard let files = entry.files, !files.isEmpty else { return }
            if files.count > 1 {
                icons = files.prefix(2).map { file in
                    var single = entry
                    single.files = [file]
                    let url = ClipboardCapture.resolvedFiles(single)?.first ?? file.url
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 256, height: 256)
                    return icon
                }
            } else {
                resolvedURL = ClipboardCapture.resolvedFiles(entry)?.first
            }
        }
    }
}
