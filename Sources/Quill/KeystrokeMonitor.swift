import Cocoa
import ApplicationServices
import Carbon.HIToolbox

/// Low-level global keyboard monitor using a CGEventTap at the HID event tap level.
/// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
/// All event processing happens on the main runloop.
final class KeystrokeMonitor {

    enum Event {
        case character(Character)
        case backspace
        case cursorMoved   // arrows, mouse, cmd/ctrl combos — assume cursor may have moved
    }

    var onEvent: ((Event) -> Void)?

    /// When true, we are injecting events ourselves — don't echo them into the matcher.
    var suspended: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        guard ensureAccessibilityPermission() else { return false }

        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mon = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
                mon.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = tap else {
            NSLog("Quill: failed to create event tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if suspended { return }

        // Re-enable tap if the OS disabled it (times out under load).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        if type == .flagsChanged { return }
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Any command / control / option combo means user is doing something
        // other than typing text (shortcuts, nav). Reset buffer.
        let modifierActive = flags.contains(.maskCommand) ||
                             flags.contains(.maskControl) ||
                             flags.contains(.maskAlternate)
        if modifierActive {
            onEvent?(.cursorMoved)
            return
        }

        switch Int(keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            onEvent?(.backspace)
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape:
            onEvent?(.cursorMoved)
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onEvent?(.character("\n"))
            return
        case kVK_Tab:
            onEvent?(.character("\t"))
            return
        case kVK_Space:
            onEvent?(.character(" "))
            return
        default:
            break
        }

        // Pull the actual unicode string the keystroke produced. This handles
        // shift, caps lock, dead keys, etc. without us re-implementing the layout.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        if length > 0 {
            let str = String(utf16CodeUnits: chars, count: length)
            for ch in str {
                onEvent?(.character(ch))
            }
        }
    }

    @discardableResult
    func ensureAccessibilityPermission() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
