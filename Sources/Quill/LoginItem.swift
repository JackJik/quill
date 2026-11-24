import Foundation
import ServiceManagement

/// Wraps SMAppService for the main app bundle. Requires macOS 13+.
enum LoginItem {

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Returns true if the state after the call matches `desired`.
    @discardableResult
    static func set(_ desired: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let svc = SMAppService.mainApp
        do {
            if desired {
                if svc.status != .enabled { try svc.register() }
            } else {
                if svc.status == .enabled { try svc.unregister() }
            }
            return true
        } catch {
            NSLog("Quill: failed to %@ login item: %@",
                  desired ? "register" : "unregister",
                  "\(error)")
            return false
        }
    }
}
