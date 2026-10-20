enum ReplyIntent: String, Codable, CaseIterable, Identifiable, Sendable {
  case accept, decline, clarify, thank, acknowledge, alternative, moreTime = "more_time"
  case apologize, support, offerHelp = "offer_help", followUp = "follow_up"

  var id: Self { self }
  var title: String {
    switch self {
    case .accept: "Accept"
    case .decline: "Decline"
    case .clarify: "Ask details"
    case .thank: "Thank them"
    case .acknowledge: "Got it"
    case .alternative: "Alternative"
    case .moreTime: "More time"
    case .apologize: "Apologize"
    case .support: "Show support"
    case .offerHelp: "Offer help"
    case .followUp: "Follow up"
    }
  }
}
