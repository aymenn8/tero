import SwiftUI

/// The same compact shell for file reviews; business choices stay in the session.
struct FileWorkflowView: View {
  @FocusState private var focusedName: Int?
  @Bindable var session: FileWorkflowSession
  var body: some View {
    VStack(spacing: 8) {
      let choices = session.presentation
      ModeChoiceRow(step: choices.step, activityTitle: choices.activityTitle, finished: choices.finished, choose: choices.activate)
      if !session.suggesting && !session.succeeded && session.detailsHeight > 0 {
        VStack(spacing: 0) {
          HStack {
            TeroModeTitle(title: session.kind.title)
            Spacer()
            if session.naming {
              Button(action: session.suggestName) { Text("⌘R").font(.system(size: 10)).foregroundStyle(.secondary) }
                .buttonStyle(TeroQuietButtonStyle()).help("Generate new names from the file contents")
                .accessibilityLabel("Regenerate filenames")
            } else {
              Text(session.urls.count == 1 ? session.urls[0].lastPathComponent : "\(session.urls.count) files")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
          }.padding(.horizontal, 12).frame(height: 30)
          TeroHeaderDivider()
          details
        }.background(TeroReadingSurface()).disabled(session.busy)
      }
      if !session.hint.isEmpty && !session.suggesting && !session.succeeded { ModeHint(text: session.hint) }
      if let message = session.message { ModeHint(text: message) }
    }
      .onChange(of: focusedName) { previous, _ in
        if let previous, session.names.indices.contains(previous) {
          session.names[previous] = FileNameProposal.formatted(session.names[previous])
        }
      }
      .frame(width: 420).padding(.horizontal, 4)
  }
  @ViewBuilder private var details: some View {
    if session.naming {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(session.urls.indices, id: \.self) { index in
            HStack(spacing: 10) {
              fileIcon(session.urls[index])
              VStack(alignment: .leading, spacing: 3) {
                Text(session.urls[index].lastPathComponent).font(.system(size: 10)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                HStack(spacing: 0) {
                  TextField("Filename", text: $session.names[index]).textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focusedName, equals: index).onSubmit(session.run)
                    .accessibilityLabel("New name for \(session.urls[index].lastPathComponent)")
                  Text(session.urls[index].pathExtension.isEmpty ? "" : "." + session.urls[index].pathExtension)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
              }
            }.padding(.horizontal, 12).frame(height: 48)
          }
        }
      }.frame(height: min(200, CGFloat(session.urls.count * 48)))
    } else if session.kind == .move {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "arrow.turn.down.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
          Image(systemName: "folder").foregroundStyle(.secondary)
          Text(session.destination?.lastPathComponent ?? "Destination").font(.system(size: 12))
            .foregroundStyle(session.destination == nil ? .white.opacity(0.4) : .white.opacity(0.85)).lineLimit(1)
          Spacer()
        }.help(session.destination?.path ?? "Choose a folder using the bubbles above").frame(height: 38)
        HStack(spacing: 5) {
          ForEach(Array(session.urls.prefix(4)), id: \.self) { fileIcon($0) }
          if session.urls.count > 4 { Text("+\(session.urls.count - 4)").font(.system(size: 10)).foregroundStyle(.secondary) }
          Spacer()
        }.frame(height: 38)
      }.padding(.horizontal, 12)
    }
  }
  private func fileIcon(_ url: URL) -> some View {
    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 24, height: 24)
      .accessibilityHidden(true)
  }
}
