import Foundation
import Observation

/// Routes "Create an action" requests from the menu and panel to the Actions settings editor.
@MainActor @Observable
final class HabitEditorRouter {
    var editorRequest: UUID?
}
