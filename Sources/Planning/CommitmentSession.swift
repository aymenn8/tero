import AppKit
import Observation

@MainActor @Observable final class CommitmentSession {
  struct Row: Identifiable {
    var id: UUID { draft.id }
    let draft: CommitmentDraft
    var selected = true
    var title: String
    var hasDate: Bool
    var hasTime: Bool
    var start: Date
    var allDay = false
    var scheduleConfirmed = false
    var zoneID: String
    var zone: TimeZone { TimeZone(identifier: zoneID) ?? .current }
    mutating func chooseZone(_ id: String) {
      guard let target = TimeZone(identifier: id) else { return }
      var source = Calendar(identifier: .gregorian); source.timeZone = zone
      var destination = Calendar(identifier: .gregorian); destination.timeZone = target
      func reinterpreted(_ value: Date) -> Date? {
        let fields = source.dateComponents([.year, .month, .day, .hour, .minute], from: value)
        guard let date = destination.date(from: fields), destination.dateComponents([.year, .month, .day, .hour, .minute], from: date) == fields else { return nil }
        return date
      }
      let newStart = reinterpreted(start), newEnd = reinterpreted(end)
      zoneID = id
      if let newStart { start = newStart } else { hasDate = false }
      if let newEnd { end = newEnd } else { hasEnd = false }
    }
    var scheduleWarning: String? {
      switch draft.scheduleIssue {
      case "ambiguous_date": "Confirm the date from the original message."
      case "ambiguous_zone": "The source time zone is ambiguous. Confirm a local time."
      case "missing_date": draft.kind == .task ? "No date was specified. Choose one or save without a due date." : "No date was specified. Choose a date for this event."
      case "missing_end": "Choose an end time or mark the event as all-day."
      case "dst_time": "This clock time is ambiguous or does not exist. Choose a valid time."
      default: nil
      }
    }
    var hasEnd: Bool
    var end: Date
    init(_ draft: CommitmentDraft) {
      self.draft = draft; title = draft.title
      let zone = draft.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
      zoneID = zone.identifier
      let components = CommitmentDraft.components(date: draft.date, time: draft.time, zone: zone)
      hasDate = components != nil; hasTime = draft.time != nil
      start = components?.date ?? .now
      let endComponents = CommitmentDraft.components(date: draft.endDate, time: draft.endTime, zone: zone)
      hasEnd = endComponents != nil; end = endComponents?.date ?? start.addingTimeInterval(3600)
      scheduleConfirmed = draft.scheduleIssue == nil
      if draft.kind == .event && draft.endTime == nil { hasEnd = false }
    }
    var valid: Bool {
      func unambiguous(_ value: Date) -> Bool {
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = zone; day.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter(); clock.locale = day.locale; clock.timeZone = zone; clock.dateFormat = "HH:mm"
        return CommitmentDraft.components(date: day.string(from: value), time: clock.string(from: value), zone: zone) != nil
      }
      return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (scheduleConfirmed || draft.scheduleIssue == nil)
        && (!hasDate || allDay || !hasTime && draft.kind == .task || unambiguous(start))
        && (draft.kind == .task || (hasDate && (allDay || (hasEnd && end > start && unambiguous(end)))))
    }
    func reviewed() -> ReviewedCommitment {
      var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
      let fields: Set<Calendar.Component> = !allDay && (hasTime || draft.kind == .event) ? [.year,.month,.day,.hour,.minute] : [.year,.month,.day]
      var startComponents = hasDate ? calendar.dateComponents(fields, from: allDay ? calendar.startOfDay(for: start) : start) : nil
      startComponents?.calendar = calendar; startComponents?.timeZone = calendar.timeZone
      let endValue = allDay ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start : end
      var endComponents = hasEnd || allDay ? calendar.dateComponents([.year,.month,.day,.hour,.minute], from: endValue) : nil
      endComponents?.calendar = calendar; endComponents?.timeZone = calendar.timeZone
      let notes = [draft.owner.map { "Source assignee: " + $0 }, draft.condition.map { "Condition: " + $0 },
        draft.deadline.map { "Original schedule: " + $0 }, "Time zone: " + zone.identifier, "Source: " + draft.evidence].compactMap { $0 }.joined(separator: "\n")
      return .init(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, start: startComponents, end: endComponents, allDay: allDay)
    }
  }
  let referenceDate = CorrectionClient.PlanningReference.current().localDate
  let destination: CommitmentDestination
  var rows: [Row]
  private(set) var containers: [PlanningContainer] = []
  var containerID = ""
  var editingRowID: UUID?
  private(set) var needsSettings = false
  private(set) var waitingForSettings = false
  private(set) var busy = false
  private(set) var created = false
  private(set) var uncertain = false
  private var cancelled = false
  private(set) var message: String?
  @ObservationIgnored private let connection: any PlanningConnection
  init(_ drafts: [CommitmentDraft], destination: CommitmentDestination, connection: (any PlanningConnection)? = nil) {
    self.destination = destination; rows = drafts.map(Row.init)
    self.connection = connection ?? ApplePlanningConnection(destination: destination)
    needsSettings = self.connection.accessDenied
    editingRowID = rows.first(where: { !$0.valid })?.id
  }
  var reviewHeight: CGFloat {
    min(280, rows.reduce(CGFloat.zero) { total, row in
      func textHeight(_ text: String) -> CGFloat {
        let bounds = (text as NSString).boundingRect(with: NSSize(width: 328, height: CGFloat.greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 11)])
        return min(28, max(14, ceil(bounds.height)))
      }
      let conditionHeight: CGFloat = row.draft.condition.map { textHeight($0) + 8 } ?? 0
      var editorHeight: CGFloat = 0
      if editingRowID == row.id {
        var lines: [CGFloat] = [22, 18]
        if row.scheduleWarning != nil { lines += [28, 18] }
        if destination == .reminders && row.hasDate { lines.append(18) }
        if destination == .calendar {
          lines += [22, 18]
          if !row.valid { lines.append(14) }
        }
        if row.draft.deadline != nil { lines.append(14) }
        editorHeight = lines.reduce(0, +) + CGFloat(lines.count - 1) * 9 + 12
      }
      return total + 91 + 20 + textHeight(row.draft.evidence) + conditionHeight + editorHeight
    } + CGFloat(max(0, rows.count - 1)) * 8)
  }
  var settingsURL: URL {
    URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" +
      (destination == .reminders ? "Privacy_Reminders" : "Privacy_Calendars"))!
  }
  func beganSettingsVisit() { waitingForSettings = true }
  var hasAccess: Bool { connection.accessGranted }
  func loadAvailableDestinations() async {
    guard !cancelled, !busy, containers.isEmpty, connection.accessGranted else { return }
    await connect()
  }
  func refreshAfterSettings() async {
    guard waitingForSettings, !cancelled, !busy, connection.accessGranted else { return }
    await connect()
  }
  var selectedRows: [Row] { rows.filter(\.selected) }
  var canCreate: Bool { !cancelled && !busy && !created && !uncertain && !selectedRows.isEmpty && selectedRows.allSatisfy(\.valid) && containers.contains { $0.id == containerID } }
  func connect() async {
    guard !cancelled, !busy else { return }; busy = true; message = nil
    defer { busy = false }
    do { let values = try await connection.connect(); guard !cancelled, !Task.isCancelled else { return }; containers = values; let preferred = UserDefaults.standard.string(forKey: destination == .calendar ? "preferredCalendarID" : "preferredReminderListID"); containerID = values.first(where: { $0.id == preferred })?.id ?? values.first?.id ?? ""; needsSettings = false; waitingForSettings = false }
    catch {
      guard !cancelled else { return }
      needsSettings = (error as? ApplePlanningConnection.Failure) == .denied
      message = needsSettings ? nil : error.localizedDescription
      if connection.accessGranted { waitingForSettings = false }
    }
  }
  func cancel() { cancelled = true }
  func create() {
    guard canCreate else { return }; busy = true; message = nil
    defer { busy = false }
    do { _ = try connection.create(selectedRows.map { $0.reviewed() }, containerID: containerID); created = true }
    catch { uncertain = true; message = error.localizedDescription }
  }
}
