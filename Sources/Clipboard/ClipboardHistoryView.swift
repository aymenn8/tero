import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var controller: PanelController
    let store: ClipboardStore
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TeroLogoMark()
                    .frame(width: 26, height: 34)
                    .overlay { WindowDragRegion().accessibilityHidden(true) }
                    .help("Drag to move")
                Button(action: controller.backFromClipboard) { Image(systemName: "chevron.left") }
                    .help("Back · esc").accessibilityLabel("Back to actions")
                if controller.clipboardActionMenuPresented {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                TextField(controller.clipboardActionMenuPresented ? "Search actions…" : "Search entries…", text: Binding(
                    get: { controller.clipboardActionMenuPresented ? controller.clipboardModeQuery : controller.clipboardQuery },
                    set: { if controller.clipboardActionMenuPresented { controller.searchClipboardModes($0) } else { controller.clipboardQuery = $0 } }))
                    .textFieldStyle(.plain).focused($focused)
                if !controller.clipboardActionMenuPresented {
                Menu {
                    Button("All Types") { controller.clipboardFilter = nil }
                    Button(controller.clipboardPinnedOnly ? "Show all entries" : "Pinned only") { controller.clipboardPinnedOnly.toggle() }
                    Divider()
                    ForEach(ClipboardKind.allCases) { kind in
                        Button(kind.title) { controller.clipboardFilter = kind }
                    }
                } label: {
                    HStack(spacing: 5) { Image(systemName: "line.3.horizontal.decrease"); Text(controller.clipboardFilter?.title ?? "All Types") }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.menuStyle(.borderlessButton).fixedSize().help("Filter by type")
                }
            }.font(.system(size: 16)).buttonStyle(.plain).padding(.horizontal, 20).frame(height: 58)
                .overlay(alignment:.bottom) {TeroHeaderDivider()}
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    // Filtered once per render; rows compare against their predecessor.
                    let entries = controller.clipboardEntries
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if entries.isEmpty {
                                Text(controller.clipboardQuery.isEmpty ? "Nothing here yet" : "No results")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                            }
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index == 0 || entry.isPinned != entries[index - 1].isPinned || (!entry.isPinned && !Calendar.current.isDate(entry.copiedAt, inSameDayAs: entries[index - 1].copiedAt)) {
                                    Text(entry.isPinned ? "Pinned" : Calendar.current.isDateInToday(entry.copiedAt) ? "Today" : Calendar.current.isDateInYesterday(entry.copiedAt) ? "Yesterday" : entry.copiedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 9).padding(.top, 8).padding(.bottom, 4)
                                }
                                Button { controller.clipboardSelectedID = entry.id } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: entry.kind.symbol).font(.system(size: 14))
                                            .frame(width: 28, height: 28)
                                            .background(.white.opacity(0.07), in: .rect(cornerRadius: 7))
                                        Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Spacer(minLength: 0)
                                        if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                                    }.padding(.horizontal, 9).frame(height: 42)
                                        .contentShape(Rectangle())
                                        .background(.white.opacity(controller.clipboardSelectedID == entry.id ? 0.1 : 0),
                                                    in: .rect(cornerRadius: 10))
                                }.buttonStyle(.plain).id(entry.id)
                                    .overlay {
                                        if entry.kind == .files {
                                            ClipboardFileDrag(entry: entry,
                                                started: { controller.beginClipboardDrag(entry) },
                                                ended: controller.endClipboardDrag,
                                                unavailable: controller.unavailableClipboardDrag)
                                        }
                                    }
                                    .help(entry.title)
                                    .contextMenu {
                                        Button("Tero actions") { controller.clipboardSelectedID = entry.id; controller.beginClipboardEntryActions() }
                                        Button(entry.isPinned ? "Unpin" : "Pin") { controller.clipboardSelectedID = entry.id; controller.toggleClipboardPin() }
                                        Divider()
                                        Button("Copy") { controller.clipboardSelectedID = entry.id; controller.useClipboardEntry(paste: false) }
                                        if entry.kind == .files {
                                            Button("Show in Finder") { controller.clipboardSelectedID = entry.id; controller.openClipboardEntry(reveal: true) }
                                        }
                                        if entry.kind == .link {
                                            Button("Open link") { controller.clipboardSelectedID = entry.id; controller.openClipboardEntry() }
                                            Button("Copy clean link") { controller.clipboardSelectedID = entry.id; controller.copyClipboardLink(domain: false) }
                                            Button("Copy domain") { controller.clipboardSelectedID = entry.id; controller.copyClipboardLink(domain: true) }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) { store.remove(entry); controller.resetClipboardSelection() }
                                    }
                            }
                        }.padding(.horizontal, 8).padding(.vertical, 4)
                    }.onChange(of: controller.clipboardSelectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }.frame(width: 255)
                Divider().opacity(0.3)
                if let entry = controller.selectedClipboardEntry {
                    ClipboardPreview(entry: entry,
                        dragStarted: { controller.beginClipboardDrag(entry) },
                        dragEnded: controller.endClipboardDrag,
                        dragUnavailable: controller.unavailableClipboardDrag).frame(maxWidth: .infinity)
                } else {
                    Text(store.enabled ? "Copy text, images or files" : "History paused")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.frame(height: 330)
            Group {
                if controller.clipboardActionMenuPresented {
                    ModeChoiceRow(step: controller.clipboardModeStep, choose: controller.chooseClipboardMode)
                        .onChange(of: controller.clipboardModeStep) { _, _ in
                            if !controller.clipboardModeStep.allows(controller.clipboardModeSelectedID) {
                                controller.clipboardModeSelectedID = controller.clipboardModeStep.choices.first?.id
                            }
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                } else {
            HStack(spacing: 12) {
                Text(controller.clipboardMessage ?? store.error ?? (controller.selectedClipboardEntry?.isPinned == true ? "Local · Pinned" : store.enabled ? "Local · 7 days" : "Paused"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                if let entry = controller.selectedClipboardEntry {
                    Button { withAnimation(.easeOut(duration: 0.18)) { controller.toggleClipboardPin() } } label: {
                        Image(systemName: entry.isPinned ? "pin.fill" : "pin").frame(width: 22, height: 22)
                    }.help(entry.isPinned ? "Unpin · ⌘P" : "Pin · ⌘P").accessibilityLabel(entry.isPinned ? "Unpin entry" : "Pin entry")
                    Button(action: controller.beginClipboardEntryActions) {
                        HStack(spacing: 6) { Text("Actions"); Text("⌘K").foregroundStyle(.secondary) }
                            .font(.system(size: 11)).padding(.horizontal, 10).frame(height: 28)
                            .background(.white.opacity(0.07), in: .capsule)
                    }.help("Apply a Tero mode to this entry")
                    Button { controller.useClipboardEntry(paste: false) } label: {
                        Image(systemName: controller.activeShortcut == "⌘C" ? "checkmark" : "doc.on.doc")
                            .frame(width: 22, height: 22).contentTransition(.symbolEffect(.replace))
                    }.help("Copy · ⌘C").accessibilityLabel("Copy entry")
                    Button(action: controller.performClipboardPrimary) {
                        HStack(spacing: 9) {
                            Text(controller.clipboardPrimaryTitle)
                            Image(systemName: "return").foregroundStyle(.secondary)
                        }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
                            .background(.white.opacity(0.07), in: .capsule)
                    }
                }
                Menu {
                    Button(store.enabled ? "Pause history" : "Enable history") { store.setEnabled(!store.enabled) }
                    if controller.selectedClipboardEntry?.kind == .link {
                        Button("Open link", action: { controller.openClipboardEntry() })
                        Button("Copy clean link", action: { controller.copyClipboardLink(domain: false) })
                        Button("Copy domain", action: { controller.copyClipboardLink(domain: true) })
                        Divider()
                    }
                    Button("Clear history…", role: .destructive) { confirmingClear = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Clipboard settings")
                    .accessibilityLabel("Clipboard settings")
            }.buttonStyle(.plain).padding(.horizontal, 16)
                }
            }.frame(height: 50)
                .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.2), value: controller.clipboardActionMenuPresented)
        }
        .modifier(ClipboardGlass())
        .scaleEffect(reduceMotion ? 1 : controller.clipboardPresented && !controller.closing ? 1 : 0.965, anchor: .top)
        .offset(y: reduceMotion ? 0 : controller.clipboardPresented && !controller.closing ? 0 : 12)
        .opacity(controller.clipboardPresented && !controller.closing ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .timingCurve(0.2, 0.85, 0.2, 1, duration: controller.clipboardClosing || controller.closing ? 0.24 : 0.34), value: controller.clipboardPresented)
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.24), value: controller.closing)
        .allowsHitTesting(!controller.clipboardClosing)
        .onChange(of: controller.clipboardSelectedID) { _, _ in controller.closeClipboardEntryMenu() }
        .onChange(of: controller.clipboardQuery) { _, _ in controller.resetClipboardSelection() }
        .onChange(of: controller.clipboardPinnedOnly) { _, _ in controller.resetClipboardSelection() }
        .onChange(of: controller.clipboardFilter) { _, _ in controller.resetClipboardSelection() }
        .onChange(of: controller.clipboardActionMenuPresented) { _, _ in focused = true }
        .task { await Task.yield(); focused = true }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { store.clear(); controller.resetClipboardSelection() }
        } message: { Text("Pinned entries will also be removed. The system clipboard stays unchanged.") }
    }
}
