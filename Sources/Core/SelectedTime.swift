import Foundation

struct SelectionTimeZone: Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  var zone: TimeZone? {
    if id.hasPrefix("offset:"), let seconds = Int(id.dropFirst(7)) { return TimeZone(secondsFromGMT: seconds) }
    return TimeZone(identifier: id)
  }
  static func fixed(_ seconds: Int, _ title: String) -> Self { .init(id: "offset:\(seconds)", title: title) }
}
struct SelectedTime: Sendable {
  let hour: Int
  let minute: Int
  let sources: [SelectionTimeZone]
  let explicitDate: String?
  static func parse(_ text: String) -> Self? {
    guard text.count <= 160, let regex = timePattern,
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
    guard var hour = group(2).flatMap(Int.init), let minute = Int(group(3) ?? "0"), (0...59).contains(minute) else { return nil }
    if let meridiem = group(4)?.uppercased() {
      guard (1...12).contains(hour) else { return nil }; hour = hour % 12 + (meridiem == "PM" ? 12 : 0)
    } else if !(0...23).contains(hour) { return nil }
    let date = group(1)
    guard date == nil || CommitmentDraft.components(date: date, time: nil) != nil,
          let name = group(5) else { return nil }
    let zones = zones(for: name.trimmingCharacters(in: .whitespaces))
    return zones.isEmpty ? nil : .init(hour: hour, minute: minute, sources: zones, explicitDate: date)
  }
  // Compiled once: `parse` runs for every action on every recommendation pass.
  private static let timePattern = try? NSRegularExpression(pattern: #"^\s*(?:(\d{4}-\d{2}-\d{2})[ T])?(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?\s+([A-Za-z_+\-/0-9: ]+)\s*$"#, options: .caseInsensitive)
  private static let offsetPattern = try? NSRegularExpression(pattern: #"^(?:UTC|GMT)([+-])(\d{1,2})(?::(\d{2}))?$"#,options:.caseInsensitive)
  private static let fixedZones: [String:[SelectionTimeZone]] = [
      "UTC":[.fixed(0,"UTC")],"GMT":[.fixed(0,"GMT")],"EST":[.fixed(-18000,"EST · UTC−5")],
      "EDT":[.fixed(-14400,"EDT · UTC−4")],"PST":[.fixed(-28800,"PST · UTC−8")],"PDT":[.fixed(-25200,"PDT · UTC−7")],
      "CET":[.fixed(3600,"CET · UTC+1")],"CEST":[.fixed(7200,"CEST · UTC+2")],
      "CST":[.fixed(-21600,"US · UTC−6"),.fixed(28800,"China · UTC+8"),.fixed(-18000,"Cuba · UTC−5")],
      "IST":[.fixed(19800,"India · UTC+5:30"),.fixed(7200,"Israel · UTC+2"),.fixed(3600,"Ireland · UTC+1")],
      "BST":[.fixed(3600,"UK · UTC+1"),.fixed(21600,"Bangladesh · UTC+6"),.fixed(39600,"Bougainville · UTC+11")],
      "AST":[.fixed(-14400,"Atlantic · UTC−4"),.fixed(10800,"Arabia · UTC+3")]
  ]
  private static let regionZones = ["ET":"America/New_York","PT":"America/Los_Angeles","CT":"America/Chicago","MT":"America/Denver",
    "LONDON":"Europe/London","PARIS":"Europe/Paris","NEW YORK":"America/New_York","TOKYO":"Asia/Tokyo"]
  static func zones(for name: String) -> [SelectionTimeZone] {
    if let zones = fixedZones[name.uppercased()] { return zones }
    if let id = regionZones[name.uppercased()] { return [.init(id: id,title: name)] }
    if let zone = TimeZone(identifier: name), name.contains("/") { return [.init(id: zone.identifier,title: name)] }
    guard let regex = offsetPattern,
          let match = regex.firstMatch(in: name,range:NSRange(name.startIndex...,in:name)) else { return [] }
    func part(_ i: Int) -> String? { Range(match.range(at:i),in:name).map { String(name[$0]) } }
    guard let hours=part(2).flatMap(Int.init),let minutes=Int(part(3) ?? "0"),hours<=14,minutes<60,hours<14 || minutes==0 else {return []}
    return [.fixed((hours*3600+minutes*60)*(part(1)=="-" ? -1:1),name.uppercased())]
  }
  /// Reject nonexistent and repeated regional wall times rather than guessing a DST fold.
  func instant(on date: String, in source: SelectionTimeZone) -> Date? {
    guard let zone=source.zone, let components=CommitmentDraft.components(date:date,time:nil) else { return nil }
    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
    var clock=components;clock.calendar=calendar;clock.timeZone=zone;clock.hour=hour;clock.minute=minute
    guard let candidate=calendar.date(from:clock) else{return nil}
    let check=calendar.dateComponents([.year,.month,.day,.hour,.minute],from:candidate)
    guard check.year==clock.year,check.month==clock.month,check.day==clock.day,check.hour==hour,check.minute==minute else{return nil}
    // A repeated clock can resolve to two instants. Compare first/last strict matches.
    let anchor=calendar.startOfDay(for:candidate).addingTimeInterval(-1)
    let first=calendar.nextDate(after:anchor,matching:DateComponents(hour:hour,minute:minute),matchingPolicy:.strict,repeatedTimePolicy:.first)
    let last=calendar.nextDate(after:anchor,matching:DateComponents(hour:hour,minute:minute),matchingPolicy:.strict,repeatedTimePolicy:.last)
    guard first==last else{return nil}
    return candidate
  }
  func result(on date: String, source: SelectionTimeZone, target: SelectionTimeZone) -> String? {
    guard let instant=instant(on:date,in:source),let from=source.zone,let to=target.zone else{return nil}
    func formatted(_ zone: TimeZone) -> String {
      let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=zone;f.dateFormat="EEE, dd MMM yyyy · HH:mm 'UTC'ZZZZZ"
      return f.string(from:instant)
    }
    return formatted(from)+"\n"+source.title+"\n\n→ "+formatted(to)+"\n"+target.title
  }
}
