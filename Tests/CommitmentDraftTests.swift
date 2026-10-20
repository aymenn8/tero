import Foundation
import Testing
@testable import TeroCore

@Test func commitmentDatesAndQuotes() {
  let source = "Maya envoie le devis demain si le budget est validé."
  var draft = CommitmentDraft(kind: .task, title: "Envoyer le devis", owner: "Maya", deadline: "demain", condition: "si le budget est validé", evidence: source, date: "2026-10-07", time: nil, endDate: nil, endTime: nil)
  #expect(draft.valid(for: source))
  draft.owner = "Lee"; #expect(!draft.valid(for: source)); draft.owner = "Maya"
  draft.date = "2026-02-30"; #expect(!draft.valid(for: source))
  draft.date = nil; draft.time = "16:00"; #expect(!draft.valid(for: source))
  #expect(CommitmentDraft.components(date: "2026--1-10", time: nil) == nil)
  #expect(CommitmentDraft.components(date: "2026-10-07", time: "25:00") == nil)
  #expect(CommitmentDraft.components(date: "2026-10-07", time: "16:00")?.hour == 16)
  draft.date = "2026-10-07"; draft.time = nil; draft.deadline = nil; #expect(!draft.valid(for: source))
}
@Test func commitmentActionsNeverReplaceText() {
  for action in [Action.createTasks, .createEvent] {
    #expect(action.definition?.usesAI == true)
    #expect(action.definition?.delivery(canReplace: true) == .interactive)
    #expect(action.definition?.transformsText == false)
  }
}

@Test func commitmentTimeZonesAndClockChanges() {
  let source = "Meeting 2026-10-06 at 15:00 EST for 90 minutes."
  var draft = CommitmentDraft(kind: .event, title: "Meeting", owner: nil, deadline: "2026-10-06 at 15:00 EST for 90 minutes", condition: nil, evidence: source, date: "2026-10-06", time: "15:00", endDate: "2026-10-06", endTime: "16:30", timeZone: "Etc/GMT+5", scheduleIssue: nil)
  #expect(draft.valid(for: source))
  let instant = CommitmentDraft.components(date: draft.date, time: draft.time, zone: TimeZone(identifier: "Etc/GMT+5")!)!.date!
  #expect(ISO8601DateFormatter().string(from: instant) == "2026-10-06T20:00:00Z")
  draft.timeZone="invented/zone";#expect(!draft.valid(for:source))
  #expect(CommitmentDraft.components(date:"2026-03-08",time:"02:30",zone:TimeZone(identifier:"America/New_York")!)==nil)
  #expect(CommitmentDraft.components(date:"2026-11-01",time:"01:30",zone:TimeZone(identifier:"America/New_York")!)==nil)
}
