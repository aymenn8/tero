import Foundation

struct CommitmentDraft: Codable, Sendable, Identifiable {
  enum Kind: String, Codable, Sendable { case task, event }
  var id = UUID()
  var kind: Kind
  var title: String
  var owner: String?
  var deadline: String?
  var condition: String?
  var evidence: String
  var date: String?
  var time: String?
  var endDate: String?
  var endTime: String?
  var timeZone: String? = nil
  var scheduleIssue: String? = nil
  enum CodingKeys: String, CodingKey { case kind, title, owner, deadline, condition, evidence, date, time, endDate, endTime, timeZone, scheduleIssue }

  func valid(for source: String) -> Bool {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 300,
          !evidence.isEmpty, source.contains(evidence), evidence.count <= 1000 else { return false }
    guard timeZone == nil || TimeZone(identifier: timeZone!) != nil,
          scheduleIssue == nil || ["ambiguous_date", "ambiguous_zone", "missing_date", "missing_end", "dst_time"].contains(scheduleIssue!) else { return false }
    return [owner, deadline, condition].allSatisfy { value in guard let value else { return true }; return !value.isEmpty && source.contains(value) }
      && (date == nil || Self.components(date: date, time: time, zone: timeZone.flatMap(TimeZone.init(identifier:)) ?? .current) != nil)
      && (endDate == nil || Self.components(date: endDate, time: endTime, zone: timeZone.flatMap(TimeZone.init(identifier:)) ?? .current) != nil)
      && (date == nil || deadline != nil) && (endDate == nil || deadline != nil)
      && (time == nil || date != nil) && (endTime == nil || endDate != nil)
  }
  static func components(date: String?, time: String?, zone: TimeZone = .current) -> DateComponents? {
    guard let date else { return nil }
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, parts.count == 3, (2000...2100).contains(parts[0]) else { return nil }
    var values = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    if let time {
      let clock = time.split(separator: ":").compactMap { Int($0) }
      guard time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil, clock.count == 2, (0...23).contains(clock[0]), (0...59).contains(clock[1]) else { return nil }
      values.hour = clock[0]; values.minute = clock[1]
    }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    guard let resolved = calendar.date(from: values) else { return nil }
    let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
    guard check.year == values.year, check.month == values.month, check.day == values.day,
          time == nil || (check.hour == values.hour && check.minute == values.minute) else { return nil }
    if time != nil {
      let anchor = calendar.startOfDay(for: resolved).addingTimeInterval(-1)
      let first = calendar.nextDate(after: anchor, matching: DateComponents(hour: values.hour, minute: values.minute), matchingPolicy: .strict, repeatedTimePolicy: .first)
      let last = calendar.nextDate(after: anchor, matching: DateComponents(hour: values.hour, minute: values.minute), matchingPolicy: .strict, repeatedTimePolicy: .last)
      guard first == last else { return nil }
    }
    values.calendar = calendar; values.timeZone = calendar.timeZone
    return values
  }
}

/// Registered destinations, independent of AI prompts. No model-generated URLs or executable code.
enum CommitmentDestination: String, CaseIterable, Identifiable, Sendable {
  case reminders, calendar
  var id: String { rawValue }
  var title: String { self == .reminders ? "Apple Reminders" : "Apple Calendar" }
  var kind: CommitmentDraft.Kind { self == .reminders ? .task : .event }
}
