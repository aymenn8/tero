import ApplicationServices

/// Synchronous, actor-local AX adapter. Each call and the total optional pass are bounded.
struct AXInvocationContextReader: InvocationContextReading {
    let application: AXUIElement
    let deadline: TimeInterval
    var canRead: Bool { !Task.isCancelled && ProcessInfo.processInfo.systemUptime < deadline }

    func text(_ attribute: InvocationContext.Attribute, from element: AXUIElement) -> String? {
        let name: String
        switch attribute {
        case .role: name = kAXRoleAttribute
        case .subrole: name = kAXSubroleAttribute
        case .title: name = kAXTitleAttribute
        case .description: name = kAXDescriptionAttribute
        case .placeholder: name = "AXPlaceholderValue"
        case .url: name = kAXURLAttribute
        }
        let value = read(name, from: element)
        if attribute == .url, let url = value as? URL { return url.absoluteString }
        return value as? String
    }

    func parent(of element: AXUIElement) -> AXUIElement? {
        unpack(read(kAXParentAttribute, from: element))
    }
    func focusedWindow() -> AXUIElement? {
        unpack(read(kAXFocusedWindowAttribute, from: application))
    }
    func characterCount(of element: AXUIElement) -> Int? {
        (read(kAXNumberOfCharactersAttribute, from: element) as? NSNumber)?.intValue
    }
    func excerpt(from element: AXUIElement, range: NSRange) -> String? {
        guard canRead else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.04)
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &raw) == .success else { return nil }
        return raw as? String
    }
    private func read(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        guard canRead else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.04)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
        return raw
    }
    private func unpack(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
}
