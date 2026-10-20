import SwiftUI

struct CommitmentContextCard: View {
  @Binding var row: CommitmentSession.Row
  let destination: CommitmentDestination
  let expanded: Bool
  let toggleEditing: () -> Void

  private var schedule: String {
    guard row.hasDate else { return destination == .calendar ? "Set time" : "No date" }
    func formatted(_ date: Date, _ pattern: String) -> String {
      let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US"); formatter.timeZone = row.zone; formatter.dateFormat = pattern
      return formatter.string(from: date)
    }
    if row.allDay { return formatted(row.start, "MMM d") + " · All day" }
    let day = formatted(row.start, "MMM d")
    let clock = formatted(row.start, "HH:mm")
    if destination == .reminders { return day + (row.hasTime ? " · " + clock : "") }
    guard row.hasEnd else { return day + " · " + clock + " · Set end" }
    let endClock = formatted(row.end, "HH:mm")
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = row.zone
    let endDay = calendar.isDate(row.start, inSameDayAs: row.end) ? "" : formatted(row.end, "MMM d") + " · "
    return day + " · " + clock + " – " + endDay + endClock
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 9) {
        Button { row.selected.toggle() } label: {
          Image(systemName: row.selected ? "checkmark.square.fill" : "square")
            .font(.system(size: 13)).foregroundStyle(.white.opacity(row.selected ? 0.8 : 0.25))
        }.buttonStyle(.plain).accessibilityLabel(row.selected ? "Exclude item" : "Include item")
        TextField("Title", text: $row.title).textFieldStyle(.plain)
          .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(row.selected ? 0.95 : 0.4))
        Button(action: toggleEditing) {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 20, height: 20)
        }.buttonStyle(TeroQuietButtonStyle()).accessibilityLabel(expanded ? "Hide details" : "Edit dates and details").help("Edit dates and details")
      }
      .frame(height: 20)
      Rectangle().fill(.white.opacity(0.065)).frame(height: 1).accessibilityHidden(true)
      Text(row.draft.evidence)
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        .help(row.draft.evidence)
      if let condition = row.draft.condition {
        Text(condition).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
          .lineLimit(2).help(condition)
      }
      HStack(spacing: 6) {
        Button(action: toggleEditing) {
          Label(schedule, systemImage: destination == .calendar ? "calendar" : "clock")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
        }
          .padding(.horizontal, 8).frame(height: 22)
          .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
          .buttonStyle(.plain)
          .help((row.draft.deadline ?? "Choose a date") + " · " + row.zone.identifier + " · One-time")
        if let owner = row.draft.owner {
          Text(owner).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            .help("Named in source; this does not assign the item")
        }
        Spacer(minLength: 0)
      }
      Text(row.zone.identifier).font(.system(size: 10)).foregroundStyle(.secondary)
      if expanded { editor.transition(.opacity) }
    }
    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(.white.opacity(row.selected ? 0.035 : 0.012), in: RoundedRectangle(cornerRadius: 10))
    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.075), lineWidth: 0.75).allowsHitTesting(false) }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 9) {
      if let warning = row.scheduleWarning {
        Text(warning).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Toggle(row.hasDate || destination == .calendar ? "Date and time reviewed" : "Save without a due date", isOn: $row.scheduleConfirmed).toggleStyle(.checkbox)
      }
      HStack {
        Toggle(destination == .reminders ? "Due" : "Start", isOn: $row.hasDate).toggleStyle(.checkbox)
        if row.hasDate {
          DatePicker("Start date", selection: $row.start, displayedComponents: (destination == .calendar && !row.allDay) || row.hasTime ? [.date, .hourAndMinute] : [.date]).labelsHidden()
        }
      }
      if destination == .reminders && row.hasDate {
        Toggle("Include time", isOn: $row.hasTime).toggleStyle(.checkbox)
      }
      if destination == .calendar {
        Toggle("All day", isOn: $row.allDay).toggleStyle(.checkbox)
        if !row.allDay { HStack {
          Toggle("End", isOn: $row.hasEnd).toggleStyle(.checkbox)
          if row.hasEnd { DatePicker("End date", selection: $row.end, displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
        }
        }
        if !row.valid { Text("Review the schedule before creating.").foregroundStyle(.secondary) }
      }
      Menu {
        ForEach(Array(Set([row.zoneID, TimeZone.current.identifier, "UTC", "Europe/Paris", "Europe/London", "America/New_York", "America/Los_Angeles", "Asia/Tokyo", "Asia/Kolkata"])).sorted(), id: \.self) { id in
          Button(id) { row.chooseZone(id) }
        }
        Menu("All time zones") {
          ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { id in Button(id) { row.chooseZone(id) } }
        }
      } label: { Text(row.zoneID).foregroundStyle(.secondary) }
        .menuStyle(.borderlessButton).help("Choose the source time zone; the entered clock time is preserved")
      if let phrase = row.draft.deadline { Text(phrase).foregroundStyle(.secondary) }
    }.font(.system(size: 11)).padding(.top, 4).environment(\.timeZone, row.zone)
  }
}
