import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hot key via Carbon's RegisterEventHotKey.
/// Unlike the keystroke monitor, this needs no Accessibility permission, so it
/// works even before/without that grant — handy for summoning the editor when
/// the menu-bar icon is hidden (e.g. behind a display notch).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let hotKeyID: EventHotKeyID

    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1

    /// `keyCode` is a virtual key code (e.g. `kVK_ANSI_Q`); `modifiers` is a
    /// Carbon modifier mask (`cmdKey | optionKey | controlKey | shiftKey`).
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress
        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        self.hotKeyID = EventHotKeyID(signature: GlobalHotKey.fourCharCode("QUIL"), id: id)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                GlobalHotKey.eventCallback,
                                                1, &eventType, nil, &handlerRef)
        guard installStatus == noErr else { return nil }

        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr, hotKeyRef != nil else {
            if let h = handlerRef { RemoveEventHandler(h) }
            return nil
        }
        GlobalHotKey.registry[id] = self
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = handlerRef { RemoveEventHandler(h) }
        GlobalHotKey.registry[hotKeyID.id] = nil
    }

    // Carbon hot-key events are delivered on the main run loop, so the handler
    // runs on the main thread and can touch UI directly.
    private static let eventCallback: EventHandlerUPP = { (_, event, _) -> OSStatus in
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        var hkID = EventHotKeyID()
        let err = GetEventParameter(event,
                                    EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID),
                                    nil,
                                    MemoryLayout<EventHotKeyID>.size,
                                    nil,
                                    &hkID)
        guard err == noErr else { return err }
        GlobalHotKey.registry[hkID.id]?.onPress()
        return noErr
    }

    private static func fourCharCode(_ s: String) -> FourCharCode {
        var result: FourCharCode = 0
        for byte in s.utf8.prefix(4) { result = (result << 8) + FourCharCode(byte) }
        return result
    }
}
