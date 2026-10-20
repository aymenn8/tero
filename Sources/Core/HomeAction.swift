enum HomeAction: String, CaseIterable, Identifiable {
    case ask, clipboard, createHabit, habits
    var id: Self { self }
    var title: String {
        switch self {
        case .ask: "Ask"
        case .clipboard: "Clipboard"
        case .createHabit: "Create an action"
        case .habits: "Actions"
        }
    }
    var iconName: String {
        switch self {
        case .ask: "bubble.left"
        case .clipboard: "doc.on.clipboard"
        case .createHabit: "plus"
        case .habits: "square.grid.2x2"
        }
    }
    var isAvailable: Bool { true }
    var accessibilityLabel: String {
        isAvailable ? title : "Custom habits — coming soon"
    }
}
