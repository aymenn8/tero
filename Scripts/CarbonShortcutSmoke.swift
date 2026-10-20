import Carbon
@main struct CarbonRoutingSmoke {
 @MainActor static func main() {
  let first = GlobalShortcutManager(), second = GlobalShortcutManager()
  var calls: [Int] = []
  first.onTrigger = { calls.append(1) }; second.onTrigger = { calls.append(2) }
  precondition(first.register(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey | optionKey)) == noErr)
  precondition(second.register(keyCode: 1, modifiers: UInt32(cmdKey | shiftKey | optionKey)) == noErr)
  for id: UInt32 in [1, 2] {
   var event: EventRef?
   precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event) == noErr)
   var identifier = EventHotKeyID(signature: 0x5445524F, id: id)
   precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier) == noErr)
   precondition(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr)
   ReleaseEvent(event)
  }
  precondition(calls == [1, 2]); first.unregister(); second.unregister()
  print("PASS: real Carbon handler dispatches each event only to its assigned shortcut")
 }
}
