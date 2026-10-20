import SwiftUI
import AppKit
import EventKit

struct PermissionSettingsView: View {
    var connectionsOnly = false
    @State private var accessibility = AXIsProcessTrusted()
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
    @State private var calendars: [PlanningContainer] = []
    @State private var lists: [PlanningContainer] = []
    @AppStorage("preferredCalendarID") private var calendarID = ""
    @AppStorage("preferredReminderListID") private var reminderID = ""
    @State private var busy = false
    @State private var message: String?
    @State private var request: Task<Void, Never>?
    @State private var eventStore = EKEventStore()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !connectionsOnly {
                SettingsGroup(title: "Selection & context") {
                    SettingsRow(title: "Accessibility", detail: "Read your selection and replace text when you choose an action.") {
                        Text(accessibility ? "Allowed" : "Not allowed").font(SettingsStyle.font(10)).foregroundStyle(SettingsStyle.secondary)
                        Button("Open System Settings") { openPermission("Accessibility") }.buttonStyle(SettingsPill())
                    }
                    SettingsDivider()
                    SettingsRow(title: "Automation", detail: "macOS asks when Tero needs to read a selection in Finder or a supported browser.") {
                        Button("Open System Settings") { openPermission("Automation") }.buttonStyle(SettingsPill())
                    }
                }
            }
            if connectionsOnly {
                SettingsGroup(title: "Apple apps") {
                    SettingsRow(title: "Calendar", detail: permissionDescription(calendarStatus)) {
                        SettingsIcon(symbol: "calendar", color: .red)
                        Button(calendarStatus == .fullAccess ? "Settings" : "Allow access") { connect(.calendar) }
                            .buttonStyle(SettingsPill()).disabled(busy)
                    }
                    if calendarStatus == .fullAccess {
                        SettingsDivider()
                        SettingsRow(title: "Default calendar") {
                            destinationPicker("Default calendar", selection: $calendarID, containers: calendars)
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: "Reminders", detail: permissionDescription(reminderStatus)) {
                        SettingsIcon(symbol: "checklist", color: .orange)
                        Button(reminderStatus == .fullAccess ? "Settings" : "Allow access") { connect(.reminders) }
                            .buttonStyle(SettingsPill()).disabled(busy)
                    }
                    if reminderStatus == .fullAccess {
                        SettingsDivider()
                        SettingsRow(title: "Default reminder list") {
                            destinationPicker("Default reminder list", selection: $reminderID, containers: lists)
                        }
                    }
                }
            }
            if !connectionsOnly {
                SettingsGroup(title: "Your data") {
                    SettingsRow(title: "Clipboard", detail: "History stays on this Mac. It isn't synced to your account.") { Image(systemName: "internaldrive").foregroundStyle(SettingsStyle.secondary) }
                    SettingsDivider()
                    SettingsRow(title: "AI actions", detail: "When you run an AI action, the content it needs goes straight from this Mac to the provider you chose in Settings → AI. With a local model, it stays on your Mac.") { EmptyView() }
                }
            } else {
                Text("Tero lets you review tasks and events before creating them. More connections will arrive in future updates.")
                    .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).lineSpacing(4)
            }
            if let message { Text(message).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
        }.onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onDisappear { request?.cancel(); request = nil }
    }
    private func destinationPicker(_ title: String, selection: Binding<String>, containers: [PlanningContainer]) -> some View {
        Menu {
            Picker(title, selection: selection) {
                Text("First available").tag("")
                ForEach(containers) { Text($0.title).tag($0.id) }
            }.pickerStyle(.inline)
        } label: {
            Text(containers.first(where: { $0.id == selection.wrappedValue })?.title ?? "First available")
                .lineLimit(1).frame(width: 176, alignment: .leading)
        }
        .frame(width: 200)
        .accessibilityLabel(title)
    }
    private func permissionDescription(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "Full access allowed."
        case .notDetermined: "Allow access to create items from your selection."
        case .writeOnly: "Full access is needed to choose a destination."
        case .denied, .restricted: "Access is disabled in System Settings."
        @unknown default: "Check access in System Settings."
        }
    }
    private func openPermission(_ name: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + name)!)
    }
    private func refresh() {
        accessibility = AXIsProcessTrusted()
        guard connectionsOnly else { return }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        if calendarStatus == .fullAccess { calendars = eventStore.calendars(for: .event).filter(\.allowsContentModifications).map { .init(id: $0.calendarIdentifier, title: $0.title) } }
        if reminderStatus == .fullAccess { lists = eventStore.calendars(for: .reminder).filter(\.allowsContentModifications).map { .init(id: $0.calendarIdentifier, title: $0.title) } }
        if calendarStatus == .fullAccess && !calendarID.isEmpty && !calendars.contains(where: { $0.id == calendarID }) { calendarID = "" }
        if reminderStatus == .fullAccess && !reminderID.isEmpty && !lists.contains(where: { $0.id == reminderID }) { reminderID = "" }
    }
    private func connect(_ destination: CommitmentDestination) {
        let status = destination == .calendar ? calendarStatus : reminderStatus
        guard status == .notDetermined else { openPermission(destination == .calendar ? "Calendars" : "Reminders"); return }
        busy = true; message = nil
        request = Task { @MainActor in
            defer { busy = false }
            do {
                let allowed = try await (destination == .calendar ? eventStore.requestFullAccessToEvents() : eventStore.requestFullAccessToReminders())
                guard !Task.isCancelled else { return }
                refresh()
                if !allowed { message = "Access wasn't granted. You can change it in System Settings." }
            } catch { if !Task.isCancelled { message = "Couldn't request access. Open System Settings to check permissions." } }
        }
    }
}
