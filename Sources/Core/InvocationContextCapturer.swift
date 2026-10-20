import Foundation

/// Same collection policy for native controls, browsers and embedded web views.
/// Does not infer site-specific modes and cannot execute an action.
enum InvocationContextCapturer {
    static func capture<Reader: InvocationContextReading>(
        using reader: Reader, focused: Reader.Element, initial: InvocationContext,
        editable: Bool, selection: NSRange?, selectedTextAvailable: Bool
    ) -> InvocationContext {
        var context = InvocationContext(capturedAt: initial.capturedAt, applicationID: initial.applicationID)
        context.applicationName = initial.applicationName
        context.capture = .partial
        func text(_ field: InvocationContext.Attribute, _ element: Reader.Element) -> String? {
            guard reader.canRead else { return nil }
            return reader.text(field, from: element).map { String($0.prefix(256)) }
        }
        guard reader.canRead else { context.limitations.insert(.readBudgetReached); return context }
        context.elementSubrole = text(.subrole, focused)
        if context.elementSubrole == "AXSecureTextField" {
            var protected = InvocationContext(capturedAt: initial.capturedAt, applicationID: initial.applicationID)
            protected.applicationName = initial.applicationName
            protected.capture = .protectedField
            return protected
        }
        context.elementRole = text(.role, focused)
        context.elementLabel = text(.title, focused)
        context.elementDescription = text(.description, focused)
        context.elementPlaceholder = text(.placeholder, focused)
        context.surface = InvocationContext.surface(role: context.elementRole, editable: editable)
        if reader.canRead, let window = reader.focusedWindow() {
            context.windowTitle = text(.title, window)
        }
        // Evidence comes from the actual ancestry, regardless of the application's identity.
        var current: Reader.Element? = focused
        for depth in 0..<16 {
            guard reader.canRead, let node = current else { break }
            let role = depth == 0 ? context.elementRole : text(.role, node)
            if depth > 0, let role {
                context.containers.append(.init(role: role, label: text(.title, node)))
            }
            if role == "AXWebArea" {
                // Unlike labels, URLs must be parsed before truncation; discard oversized URLs.
                if reader.canRead, let raw = reader.text(.url, from: node) {
                    context.webHost = InvocationContext.host(from: raw)
                }
                if context.webHost == nil { context.limitations.insert(.webLocationUnavailable) }
                break
            }
            guard reader.canRead else { break }
            current = reader.parent(of: node)
            if depth == 15, current != nil { context.limitations.insert(.ancestorLimitReached) }
        }
        if reader.canRead, selectedTextAvailable, let selection,
           let count = reader.characterCount(of: focused),
           let range = InvocationContext.excerptRange(selection: selection, total: count),
           range.length > 0, reader.canRead {
            // Re-check before content access; the focused control could have become protected.
            let subrole = reader.text(.subrole, from: focused)
            if subrole == "AXSecureTextField" {
                var protected = InvocationContext(capturedAt: initial.capturedAt, applicationID: initial.applicationID)
                protected.applicationName = initial.applicationName
                protected.capture = .protectedField
                return protected
            }
            if reader.canRead {
                context.nearbyText = reader.excerpt(from: focused, range: range).map { String($0.prefix(960)) }
            }
        }
        if !reader.canRead { context.limitations.insert(.readBudgetReached) }
        if context.elementRole == nil { context.limitations.insert(.roleUnavailable) }
        if context.windowTitle == nil { context.limitations.insert(.windowUnavailable) }
        if selectedTextAvailable && context.nearbyText == nil { context.limitations.insert(.excerptUnavailable) }
        // Completed metadata with unavailable fields keeps those individual facts unknown.
        context.capture = reader.canRead && context.elementRole != nil ? .observed : .partial
        return context
    }
}
