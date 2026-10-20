import AppKit
import SwiftUI

struct CommitmentReviewView: View {
  @Bindable var session: CommitmentSession
  let openSettings: () -> Void
  let close: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TeroModeTitle(title:session.destination == .reminders ? "Create tasks" : "Add to Calendar")
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay { WindowDragRegion().accessibilityHidden(true) }
          .help("Drag to move")
        Button(action: close) {
          Image(systemName: "xmark").frame(width: 20, height: 20)
        }
        .buttonStyle(TeroQuietButtonStyle()).font(.system(size: 11, weight: .medium))
        .accessibilityLabel("Close review").help("Close · esc")
      }.frame(height: 20)
        .overlay(alignment:.bottom) {TeroHeaderDivider().padding(.horizontal,-14).offset(y:6)}
      if session.rows.isEmpty {
        Text(session.destination == .reminders ? "No pending tasks found." : "No appointments found.")
          .font(.system(size: 13)).foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(spacing: 8) {
            ForEach($session.rows) { $row in
              CommitmentContextCard(row: $row, destination: session.destination,
                expanded: session.editingRowID == row.id) {
                  withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    session.editingRowID = session.editingRowID == row.id ? nil : row.id
                  }
                }
            }
          }
        }
        .frame(height: session.reviewHeight).scrollBounceBehavior(.basedOnSize)
        .disabled(session.busy || session.created)
        footer
      }
      if let message = session.message {
        Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
    .padding(14).frame(width: 380).tint(.white)
    .background { TeroReadingSurface() }
    .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    .opacity(revealed ? 1 : 0).offset(y: revealed || reduceMotion ? 0 : 3)
    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22), value: revealed)
    .onAppear { revealed = true }
    .task { await session.loadAvailableDestinations() }
    .task(id: session.created) {
      guard session.created else { return }
      // Keep the confirmation readable, then use the shared panel close animation.
      // SwiftUI cancels this task if the review is dismissed or replaced.
      do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
      guard !Task.isCancelled, session.created else { return }
      close()
    }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
      Task { await session.refreshAfterSettings() }
    }
  }

  @ViewBuilder private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if session.needsSettings {
        Text("Enable Tero in Privacy & Security.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        if session.containers.isEmpty {
          Text(session.destination == .reminders ? "Reminders" : "Calendar")
            .font(.system(size: 11)).foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Button(action: {
            if session.needsSettings { openSettings() }
            else { Task { await session.connect() } }
          }) {
            HStack(spacing: 7) {
              if session.busy { ReadingActivityGlyph().accessibilityHidden(true) }
              Text(session.busy ? "Connecting…" : session.needsSettings ? "Open Settings" : session.hasAccess ? "Try again" : "Allow access")
            }
              .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
              .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
          }.buttonStyle(TeroQuietButtonStyle()).disabled(session.busy)
            .help(session.needsSettings ? "Open privacy settings · ↵" : "Allow access · ↵")
        } else {
          Menu {
            ForEach(session.containers) { container in
              Button(container.title) { session.containerID = container.id }
            }
          } label: {
            HStack(spacing: 5) {
              Text(session.containers.first { $0.id == session.containerID }?.title ?? "Choose destination").lineLimit(1)
              Image(systemName: "chevron.down").font(.system(size: 8))
            }.font(.system(size: 11)).foregroundStyle(.secondary)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .help("Choose a list or calendar · One-time items")
            .disabled(session.busy || session.created)
          Spacer(minLength: 8)
          Button(action: session.create) {
            HStack(spacing: 8) {
              Text(session.created ? "Created" : "Create \(session.selectedRows.count)")
              if !session.created { Text("⌘↵").foregroundStyle(.secondary).font(.system(size: 10)) }
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
              .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
          }.buttonStyle(TeroQuietButtonStyle()).keyboardShortcut(.return, modifiers: .command).disabled(!session.canCreate)
        }
      }
    }
  }
}
