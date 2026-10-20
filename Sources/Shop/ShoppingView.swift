import SwiftUI
import AppKit

struct ShoppingView: View {
    let session: ShoppingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TeroModeTitle(title: "Ask", loading: session.busy)
                    .overlay { WindowDragRegion().accessibilityHidden(true) }
                Spacer()
                Button(action: session.back) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .accessibilityLabel("Close Ask").help("Close · Esc")
            }
            .frame(height: 28)

            if !session.composing {
                ActivityLabel(title: session.request, active: session.busy, inactiveOpacity: 0.55).font(.system(size: 12)).lineLimit(2)
            }
            if let result = session.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(result.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(result.products) { product in
                            HStack(alignment: .top, spacing: 12) {
                                if let image = product.image {
                                    AsyncImage(url: image) { phase in
                                        if let image = phase.image { image.resizable().scaledToFit().accessibilityLabel(product.name) }
                                        else { Image(systemName: "bag").foregroundStyle(.secondary) }
                                    }.frame(width: 62, height: 62).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(product.name).font(.system(size: 13, weight: .semibold))
                                        Spacer(minLength: 6)
                                        Text(product.price).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    Text(product.reason).font(.system(size: 12)).lineSpacing(2)
                                    if !product.tradeoff.isEmpty { Text(product.tradeoff).font(.system(size: 11)).foregroundStyle(.secondary) }
                                    if let link = product.link {
                                        HStack(spacing: 5) {
                                            Text(link.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                                                .foregroundStyle(.secondary)
                                            Button { NSWorkspace.shared.open(link) } label: {
                                                Image(systemName: "arrow.up.right").frame(width: 24, height: 24)
                                            }.accessibilityLabel("View \(product.name)").help("View product in your browser")
                                        }.font(.system(size: 11))
                                    }
                                }
                            }
                            if product.id != result.products.last?.id { Divider().opacity(0.4) }
                        }
                    }.textSelection(.enabled).padding(.vertical, 3)
                }.frame(maxHeight: .infinity)
            } else if !session.composing {
                Text(session.busy ? "Finding products for you…" : "Add details to refine your search.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 10) {
                AskPromptEditor(query: session.composing ? session.draft : session.preferences, update: { if session.composing { session.draft = $0 } else { session.preferences = $0 } }, submit: { session.search() }, enabled: !session.busy, accessibilityLabel: session.composing ? "Product request" : session.result == nil ? "Budget and preferences, optional" : "Refine product search", accessibilityHelp: "Return to search. Shift Return for a new line. Command S to skip optional preferences.")
                    .frame(height: session.editorHeight)
                    .overlay(alignment: .topLeading) {
                        if session.composing ? session.draft.isEmpty : session.preferences.isEmpty {
                            Text(session.composing ? "What are you looking for?" : session.result == nil ? "Budget, country, preferences…" : "Less expensive, quieter, wireless…")
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).allowsHitTesting(false)
                        }
                    }
                HStack {
                    if !session.busy && !session.composing && session.result == nil {
                        Button { session.search(skip: true) } label: {
                            Image(systemName: "forward.end").frame(width: 28, height: 28)
                        }.keyboardShortcut("s", modifiers: .command)
                            .accessibilityLabel("Skip preferences and search").help("Skip preferences · ⌘S")
                    }
                    Spacer()
                    Button { session.search() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }.accessibilityLabel(session.composing ? "Continue · Return" : "Search products · Return")
                    .help(session.composing ? "Continue · Return" : "Search · Return")
                    .disabled(session.busy || (session.composing && session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (session.result != nil && session.preferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }.frame(height: 28)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { if session.result != nil { TeroHeaderDivider() } }
            if let error = session.error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.padding(14).frame(width: 440, height: session.height, alignment: .topLeading)
            .foregroundStyle(.white.opacity(0.9)).buttonStyle(TeroQuietButtonStyle())
            .background { TeroReadingSurface() }
            .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
            .onChange(of: session.height) { _, _ in session.changed() }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.composing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.result != nil)
    }
}
