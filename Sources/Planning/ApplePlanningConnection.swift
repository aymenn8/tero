import EventKit
import Foundation

struct PlanningContainer: Identifiable { let id: String; let title: String }
struct ReviewedCommitment {
  let title: String
  let notes: String
  let start: DateComponents?
  let end: DateComponents?
  var allDay = false
}
@MainActor protocol PlanningConnection {
  var accessGranted: Bool { get }
  var accessDenied: Bool { get }
  func connect() async throws -> [PlanningContainer]
  func create(_ items: [ReviewedCommitment], containerID: String) throws -> Int
}

@MainActor final class ApplePlanningConnection: PlanningConnection {
  let destination: CommitmentDestination
  private lazy var store = EKEventStore()
  init(destination: CommitmentDestination) { self.destination = destination }
  enum Failure: Error, LocalizedError, Equatable {
    case denied, noList, invalid, save
    var errorDescription: String? {
      switch self {
      case .denied: "Allow access in System Settings to continue."
      case .noList: "No writable list or calendar is available."
      case .invalid: "Review titles, dates and the destination before creating."
      case .save: "Couldn't confirm creation. Check the destination before trying again."
      }
    }
  }
  var accessGranted: Bool {
    EKEventStore.authorizationStatus(for: destination == .reminders ? .reminder : .event) == .fullAccess
  }
  var accessDenied: Bool {
    switch EKEventStore.authorizationStatus(for: destination == .reminders ? .reminder : .event) {
    case .denied, .restricted, .writeOnly: true
    default: false
    }
  }
  func connect() async throws -> [PlanningContainer] {
    let granted = try await (destination == .reminders ? store.requestFullAccessToReminders() : store.requestFullAccessToEvents())
    guard granted else { throw Failure.denied }
    let kind: EKEntityType = destination == .reminders ? .reminder : .event
    let values = store.calendars(for: kind).filter(\.allowsContentModifications)
    guard !values.isEmpty else { throw Failure.noList }
    return values.map { .init(id: $0.calendarIdentifier, title: $0.title) }
  }
  func create(_ items: [ReviewedCommitment], containerID: String) throws -> Int {
    guard !items.isEmpty, items.count <= 8,
          let calendar = store.calendar(withIdentifier: containerID), calendar.allowsContentModifications,
          calendar.allowedEntityTypes.contains(destination == .reminders ? .reminder : .event) else { throw Failure.invalid }
    for item in items {
      guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid }
      if destination == .calendar {
        guard let start = item.start?.date, let end = item.end?.date, end > start else { throw Failure.invalid }
      }
    }
    do {
      for item in items {
        if destination == .reminders {
          let reminder = EKReminder(eventStore: store)
          reminder.calendar = calendar; reminder.title = item.title; reminder.notes = item.notes
          reminder.dueDateComponents = item.start
          try store.save(reminder, commit: false)
        } else {
          let event = EKEvent(eventStore: store)
          event.calendar = calendar; event.title = item.title; event.notes = item.notes
          event.startDate = item.start?.date; event.endDate = item.end?.date
          event.timeZone = item.start?.timeZone ?? .current
          event.isAllDay = item.allDay
          try store.save(event, span: .thisEvent, commit: false)
        }
      }
      try store.commit()
      return items.count
    } catch { store.reset(); throw Failure.save }
  }
}
