import ApplicationServices

/// AX IPC runs outside the UI actor and has a short per-request timeout.
actor SelectionEngine {
  private var enabledProcesses: Set<Int32> = []
  private var target: (id: UUID, element: AXUIElement)?
  /// Prepare deferred web accessibility before a user selects text. Enabling it
  /// only at invocation can rebuild a virtual editor's input and lose its AX range.
  /// This requests support only; it never reads or stores the current selection.
  func prepareAccessibility(processIdentifier: Int32) async {
    if AXIsProcessTrusted(), !enabledProcesses.contains(processIdentifier) {
      let app = AXUIElementCreateApplication(processIdentifier)
      AXUIElementSetMessagingTimeout(app, 0.15)
      // Request the deferred Electron/Chromium accessibility tree, when supported.
      var enabled = false
      for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
        if AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue) == .success {
          enabled = true
        }
      }
      if let window = attribute(kAXFocusedWindowAttribute as CFString, from: app)
          ?? attribute(kAXMainWindowAttribute as CFString, from: app),
         CFGetTypeID(window) == AXUIElementGetTypeID(),
         AXUIElementSetAttributeValue(unsafeDowncast(window, to: AXUIElement.self),
           "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success { enabled = true }
      if enabled { enabledProcesses.insert(processIdentifier) }
      if enabled { try? await Task.sleep(for: .milliseconds(100)) }
    }
  }

  func capture(applicationName: String, processIdentifier: Int32, applicationID: String? = nil) async -> SelectionReadout {
    target = nil
    await prepareAccessibility(processIdentifier: processIdentifier)
    let first = readSelection(applicationName: applicationName, processIdentifier: processIdentifier, applicationID: applicationID)
    guard [.unavailable, .unsupported, .noSelection].contains(first.status), !Task.isCancelled else { return first }
    // A busy AX server or a focus transition can fail transiently. Retry once before
    // showing UI; a failed first snapshot never grants a replacement target.
    do { try await Task.sleep(for: .milliseconds(60)) } catch { return first }
    target = nil
    return readSelection(applicationName: applicationName, processIdentifier: processIdentifier, applicationID: applicationID)
  }

  private func readSelection(applicationName: String, processIdentifier: Int32, applicationID: String?) -> SelectionReadout
  {
    var context = InvocationContext(capturedAt: .now, applicationID: applicationID)
    context.applicationName = String(applicationName.prefix(128))
    func result(_ status: SelectionReadout.Status, metadata: SelectionMetadata? = nil)
      -> SelectionReadout
    {
      SelectionReadout(
        applicationName: applicationName, processIdentifier: processIdentifier,
        status: status, context: context, metadata: metadata)
    }
    guard AXIsProcessTrusted() else { return result(.permissionRequired) }
    let application = AXUIElementCreateApplication(processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.15)
    var focusedValue: CFTypeRef?
    let focusError = AXUIElementCopyAttributeValue(
      application, kAXFocusedUIElementAttribute as CFString, &focusedValue)
    let focusWasExposed = focusError == .success && focusedValue.map {
      CFGetTypeID($0) == AXUIElementGetTypeID()
    } == true
    let originalFocus: AXUIElement
    if focusWasExposed, let focusedValue {
      originalFocus = unsafeDowncast(focusedValue, to: AXUIElement.self)
    } else if [.success, .noValue, .attributeUnsupported, .notImplemented].contains(focusError),
              let window = attribute(kAXFocusedWindowAttribute as CFString, from: application)
                ?? attribute(kAXMainWindowAttribute as CFString, from: application),
              CFGetTypeID(window) == AXUIElementGetTypeID() {
      // Selecting document text need not assign an AX keyboard-focus element.
      // Search the current window instead of treating missing focus as an empty selection.
      originalFocus = unsafeDowncast(window, to: AXUIElement.self)
    } else {
      return result(failure(for: focusError))
    }
    var focused = originalFocus
    AXUIElementSetMessagingTimeout(focused, 0.15)

    var subrole: CFTypeRef?
    let subroleError = AXUIElementCopyAttributeValue(
      focused, kAXSubroleAttribute as CFString, &subrole)
    if subrole as? String == kAXSecureTextFieldSubrole {
      context.capture = .protectedField
      return result(.protectedField)
    }
    // A broken or inaccessible object should not be probed for content.
    guard [.success, .attributeUnsupported, .noValue].contains(subroleError) else {
      return result(failure(for: subroleError))
    }

    var selectedValue: CFTypeRef?
    var error = AXUIElementCopyAttributeValue(
      focused, kAXSelectedTextAttribute as CFString, &selectedValue)
    var marker: CFTypeRef?
    if (selectedValue as? String)?.isEmpty != false,
       let webSelection = markerSelection(focused) {
      selectedValue = webSelection.text as CFString
      marker = webSelection.marker
      error = .success
    }
    // Page/message selection can live outside the still-focused empty composer.
    // Read only explicit selected text in this window; never infer it from AXValue.
    if (selectedValue as? String)?.isEmpty != false,
       [.success, .noValue, .attributeUnsupported, .notImplemented].contains(error),
       let candidate = selectedElement(in: application, originalFocus: originalFocus) {
      focused = candidate.element
      selectedValue = candidate.text as CFString
      marker = candidate.marker
      error = .success
    }
    guard !Task.isCancelled else { return result(.unavailable) }
    let observedMetadata = readMetadata(focused)
    let selectionOwnsFocus = focusWasExposed && CFEqual(focused, originalFocus)
    let metadata = selectionOwnsFocus && marker == nil ? observedMetadata : SelectionMetadata(
      range: observedMetadata.range, controlBounds: observedMetadata.controlBounds,
      selectionBounds: observedMetadata.selectionBounds, isEditable: false)
    context = readContext(application: application, focused: focused, metadata: metadata,
                          initial: context, selectedTextAvailable: error == .success)
    // The optional context reader temporarily lowers these objects' timeouts to
    // 40 ms. Critical selection validation must keep its original 150 ms budget.
    AXUIElementSetMessagingTimeout(application, 0.15)
    AXUIElementSetMessagingTimeout(focused, 0.15)
    // Discard mixed snapshots if focus changed while the additional AX reads were running.
    let latestFocus = focusWasExposed
      ? attribute(kAXFocusedUIElementAttribute as CFString, from: application)
      : (attribute(kAXFocusedWindowAttribute as CFString, from: application)
          ?? attribute(kAXMainWindowAttribute as CFString, from: application))
    guard let latestFocus, CFGetTypeID(latestFocus) == AXUIElementGetTypeID(),
          CFEqual(latestFocus, originalFocus) else {
      context = InvocationContext(capturedAt: context.capturedAt, applicationID: applicationID)
      context.applicationName = String(applicationName.prefix(128))
      return result(.unavailable)
    }
    if context.capture == .protectedField { return result(.protectedField) }
    guard error == .success else { return result(failure(for: error), metadata: metadata) }
    guard let text = selectedValue as? String else { return result(.unavailable) }
    // The same element may remain focused while its selection changes. Do not mix old text
    // with newer surrounding content or register a paste target from that mixed snapshot.
    var latestRange = CFRange()
    let latestRangeValue = attribute(kAXSelectedTextRangeAttribute as CFString, from: focused)
    let hasLatestRange = unpack(latestRangeValue, type: .cfRange, into: &latestRange)
    let validLatestRange = hasLatestRange
      ? SelectionMetadata.validRange(location: latestRange.location, length: latestRange.length) : nil
    let latestText: String?
    let markerUnchanged: Bool
    if let marker {
      let latest = markerSelection(focused)
      latestText = latest?.text
      markerUnchanged = latest.map { CFEqual(marker, $0.marker) } ?? false
    } else {
      latestText = attribute(kAXSelectedTextAttribute as CFString, from: focused) as? String
      markerUnchanged = true
    }
    guard markerUnchanged, attribute(kAXSubroleAttribute as CFString, from: focused) as? String != kAXSecureTextFieldSubrole,
          latestText == text,
          validLatestRange == metadata.range else {
      context = InvocationContext(capturedAt: context.capturedAt, applicationID: applicationID)
      context.applicationName = String(applicationName.prefix(128))
      return result(.unavailable)
    }
    var readout = result(SelectionReadout.status(for: text), metadata: metadata)
    if selectionOwnsFocus && marker == nil && (!text.isEmpty || (metadata.isEditable && metadata.range?.length == 0)) {
      let id = UUID()
      target = (id, focused)
      readout.targetID = id
    }
    return readout
  }

  /// Web document selections can use opaque markers instead of AXSelectedText.
  /// Only the explicitly selected range is read; this never grants a paste target.
  private func markerSelection(_ element: AXUIElement) -> (text: String, marker: CFTypeRef)? {
    guard !Task.isCancelled else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.04)
    for (attributeName, stringName) in [
      ("AXSelectedTextMarkerRange", "AXStringForTextMarkerRange"),
      (kAXSelectedTextRangeAttribute, kAXStringForRangeParameterizedAttribute)
    ] {
      var marker: CFTypeRef?
      guard !Task.isCancelled,
        AXUIElementCopyAttributeValue(element, attributeName as CFString,
                                       &marker) == .success, let marker else { continue }
      if attributeName == kAXSelectedTextRangeAttribute {
        var range = CFRange()
        guard unpack(marker, type: .cfRange, into: &range), range.location >= 0,
              range.length > 0 else { continue }
      }
      var raw: CFTypeRef?
      if !Task.isCancelled,
        AXUIElementCopyParameterizedAttributeValue(element, stringName as CFString,
                                                   marker, &raw) == .success,
        let text = raw as? String, !text.isEmpty { return (text, marker) }
    }
    return nil
  }

  private func selectedElement(in application: AXUIElement, originalFocus: AXUIElement)
    -> (element: AXUIElement, text: String, marker: CFTypeRef?)? {
    let deadline = ProcessInfo.processInfo.systemUptime + 0.65
    var seen: [AXUIElement] = [originalFocus]
    func read(_ name: CFString, _ element: AXUIElement, timeout: Float = 0.04) -> CFTypeRef? {
      guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
      AXUIElementSetMessagingTimeout(element, timeout)
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
      return value
    }
    func element(_ value: CFTypeRef?) -> AXUIElement? {
      guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
      return unsafeDowncast(value, to: AXUIElement.self)
    }
    func canProbe(_ node: AXUIElement) -> Bool {
      guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return false }
      AXUIElementSetMessagingTimeout(node, 0.04)
      var subrole: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(node, kAXSubroleAttribute as CFString, &subrole)
      return [.success, .attributeUnsupported, .noValue].contains(error)
        && subrole as? String != kAXSecureTextFieldSubrole
    }
    func selected(_ node: AXUIElement) -> (AXUIElement, String, CFTypeRef?)? {
      guard canProbe(node) else { return nil }
      if let text = read(kAXSelectedTextAttribute as CFString, node, timeout: 0.15) as? String,
         !text.isEmpty { return (node, text, nil) }
      if ProcessInfo.processInfo.systemUptime < deadline, let selection = markerSelection(node) {
        return (node, selection.text, selection.marker)
      }
      return nil
    }
    var ancestor = originalFocus
    for _ in 0..<8 {
      guard let parent = element(read(kAXParentAttribute as CFString, ancestor)),
            !seen.contains(where: { CFEqual($0, parent) }) else { break }
      seen.append(parent)
      if let selection = selected(parent) { return selection }
      ancestor = parent
    }
    guard let window = element(read(kAXFocusedWindowAttribute as CFString, application))
      ?? element(read(kAXMainWindowAttribute as CFString, application)) else { return nil }
    var queue: [(AXUIElement, Int)] = [(window, 0)]
    var index = 0
    while index < queue.count, index < 512, !Task.isCancelled,
          ProcessInfo.processInfo.systemUptime < deadline {
      let (node, depth) = queue[index]; index += 1
      let visited = seen.contains { CFEqual($0, node) }
      if !visited {
        seen.append(node)
        if let selection = selected(node) { return selection }
      }
      guard depth < 32, queue.count < 512,
            canProbe(node), !Task.isCancelled,
            ProcessInfo.processInfo.systemUptime < deadline else { continue }
      AXUIElementSetMessagingTimeout(node, 0.04)
      var childCount: CFIndex = 0
      guard AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &childCount) == .success,
            childCount > 0, !Task.isCancelled,
            ProcessInfo.processInfo.systemUptime < deadline else { continue }
      var children: CFArray?
      if AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0,
          min(childCount, 128, 512 - queue.count), &children) == .success,
         let children = children as? [AXUIElement] {
        for child in children where !queue.contains(where: { CFEqual($0.0, child) }) {
          queue.append((child, depth + 1))
        }
      }
    }
    return nil
  }

  private func readContext(application: AXUIElement, focused: AXUIElement,
                           metadata: SelectionMetadata, initial: InvocationContext,
                           selectedTextAvailable: Bool) -> InvocationContext {
    let reader = AXInvocationContextReader(application: application,
      deadline: ProcessInfo.processInfo.systemUptime + 0.35)
    return InvocationContextCapturer.capture(using: reader, focused: focused, initial: initial,
      editable: metadata.isEditable, selection: metadata.range, selectedTextAvailable: selectedTextAvailable)
  }

  func clearTarget(_ id: UUID?) {
    if target?.id == id { target = nil }
  }

  func validatesClipboardTarget(_ original: SelectionReadout) -> Bool {
    validatesTarget(original, clipboard: true)
  }

  func validatesPasteTarget(_ original: SelectionReadout) -> Bool {
    validatesTarget(original, clipboard: false)
  }

  private func validatesTarget(_ original: SelectionReadout, clipboard: Bool) -> Bool {
    guard !Task.isCancelled, AXIsProcessTrusted(), (clipboard ? original.canInsertClipboard : original.canPaste),
      let target, target.id == original.targetID,
      let expectedRange = original.metadata?.range
    else { return false }
    let expectedText: String
    if case .selected(let text) = original.status { expectedText = text } else { expectedText = "" }
    let app = AXUIElementCreateApplication(original.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.15)
    guard let rawFocus = attribute(kAXFocusedUIElementAttribute as CFString, from: app),
      CFGetTypeID(rawFocus) == AXUIElementGetTypeID(),
      CFEqual(rawFocus, target.element),
      attribute(kAXSubroleAttribute as CFString, from: target.element) as? String
        != kAXSecureTextFieldSubrole,
      attribute(kAXSelectedTextAttribute as CFString, from: target.element) as? String
        == expectedText
    else { return false }
    let current = readMetadata(target.element)
    return !Task.isCancelled && current.isEditable && current.range == expectedRange
  }

  private func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    guard !Task.isCancelled else { return nil }
    // Also restore the captured target's timeout before later paste validation.
    AXUIElementSetMessagingTimeout(element, 0.15)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
  }

  private func unpack<T>(_ raw: CFTypeRef?, type: AXValueType, into value: inout T) -> Bool {
    guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
    let wrapped = unsafeDowncast(raw, to: AXValue.self)
    guard AXValueGetType(wrapped) == type else { return false }
    return withUnsafeMutablePointer(to: &value) { pointer in
      AXValueGetValue(wrapped, type, pointer)
    }
  }

  private func readMetadata(_ focused: AXUIElement) -> SelectionMetadata {
    var range = CFRange()
    let rangeValue = attribute(kAXSelectedTextRangeAttribute as CFString, from: focused)
    let hasRange = unpack(rangeValue, type: .cfRange, into: &range)
    let validRange =
      hasRange ? SelectionMetadata.validRange(location: range.location, length: range.length) : nil

    var position = CGPoint.zero
    var size = CGSize.zero
    let hasPosition = unpack(
      attribute(kAXPositionAttribute as CFString, from: focused), type: .cgPoint, into: &position)
    let hasSize = unpack(
      attribute(kAXSizeAttribute as CFString, from: focused), type: .cgSize, into: &size)
    let controlRect = CGRect(origin: position, size: size)
    let controlBounds =
      hasPosition && hasSize && PanelPlacement.validBounds(controlRect) ? controlRect : nil

    var settable: DarwinBoolean = false
    let editable =
      !Task.isCancelled
      && AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable)
        == .success
      && settable.boolValue

    var selectionBounds: CGRect?
    if !Task.isCancelled, validRange != nil, range.length > 0, let rangeValue {
      var rawBounds: CFTypeRef?
      var bounds = CGRect.zero
      if AXUIElementCopyParameterizedAttributeValue(
        focused, kAXBoundsForRangeParameterizedAttribute as CFString,
        rangeValue, &rawBounds) == .success,
        unpack(rawBounds, type: .cgRect, into: &bounds), PanelPlacement.validBounds(bounds)
      {
        selectionBounds = bounds
      }
    }
    return SelectionMetadata(
      range: validRange, controlBounds: controlBounds,
      selectionBounds: selectionBounds, isEditable: editable)
  }

  private func failure(for error: AXError) -> SelectionReadout.Status {
    if !AXIsProcessTrusted() { return .permissionRequired }
    switch error {
    case .attributeUnsupported, .notImplemented: return .unsupported
    case .noValue: return .noSelection
    default: return .unavailable
    }
  }
}
