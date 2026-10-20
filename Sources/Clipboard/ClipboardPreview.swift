import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardPreview: View {
    let entry: ClipboardEntry
    var dragStarted: () -> Void = {}
    var dragEnded: (Bool) -> Void = { _ in }
    var dragUnavailable: () -> Void = {}
    @State private var previewImage: NSImage?

    private var previewAllowsFileDrag: Bool {
        guard let files = entry.files else { return false }
        if files.count > 1 { return true }
        guard let file = files.first, let type = UTType(filenameExtension: file.url.pathExtension) else { return true }
        // Leave the native audio/video transport controls free to handle scrubbing.
        return !type.conforms(to: .audio) && !type.conforms(to: .movie)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entry.kind == .files {
                ClipboardFilePreview(entry: entry).id(entry.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if previewAllowsFileDrag {
                            ClipboardFileDrag(entry: entry, started: dragStarted,
                                              ended: dragEnded, unavailable: dragUnavailable)
                        }
                    }
            } else {
                ScrollView {
                    Group {
                        if entry.kind == .image, let previewImage {
                            Image(nsImage: previewImage).resizable().scaledToFit()
                                .frame(maxHeight: 165).clipShape(.rect(cornerRadius: 8))
                        } else {
                            Text(entry.text).font(.system(size: 13, design: entry.kind == .link ? .default : .monospaced))
                                .lineSpacing(4)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                ClipboardInfoRow(label: "Source", value: entry.sourceName ?? "Unknown", shaded: true)
                ClipboardInfoRow(label: "Type", value: entry.kind == .files && entry.files?.count == 1 ? "File" : entry.kind.title)
                if entry.kind == .text {
                    ClipboardInfoRow(label: "Characters", value: String(entry.text.count), shaded: true)
                    ClipboardInfoRow(label: "Words", value: String(entry.text.split(whereSeparator: \.isWhitespace).count))
                } else if entry.kind == .image {
                    ClipboardInfoRow(label: "Dimensions", value: "\(entry.pixelWidth ?? 0) × \(entry.pixelHeight ?? 0)", shaded: true)
                    ClipboardInfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                } else if entry.kind == .files {
                    ClipboardInfoRow(label: "Location", value: entry.files?.first?.url.deletingLastPathComponent().path ?? "—", shaded: true)
                    ClipboardInfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                } else if let host = entry.webURL?.host {
                    ClipboardInfoRow(label: "Domain", value: host, shaded: true)
                }
                ClipboardInfoRow(label: "Copied", value: entry.copiedAt.formatted(date: .abbreviated, time: .shortened), shaded: true)
                ClipboardInfoRow(label: "Copies", value: String(entry.copies ?? 1))
            }
        }.padding(16)
        .task(id: entry.id) {
            previewImage = entry.imageData.flatMap { NSImage(data: $0) }
        }
    }
}
