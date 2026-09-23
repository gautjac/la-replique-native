import Foundation

extension Notification.Name {
    static let findOpen = Notification.Name("LaReplique.findOpen")
    static let findNext = Notification.Name("LaReplique.findNext")
    static let findPrevious = Notification.Name("LaReplique.findPrevious")
}

#if os(macOS)
import AppKit

/// SwiftUI's default Edit ▸ Find menu owns ⌘F, ⌘G and ⇧⌘G and sends them as
/// `performTextFinderAction:`. The moment a text field is first responder its
/// field editor (an NSTextView) answers that selector — so the key equivalents
/// were eaten silently and never reached the find bar's buttons (Jac, 2026-09-23:
/// « ⌘G doesn't scroll to the next match »). Menu key equivalents are resolved
/// before the responder chain sees the key, so the fix is to make those three
/// items OURS: same shortcuts, our actions.
@MainActor
final class FindMenuBridge: NSObject {
    static let shared = FindMenuBridge()

    @objc func open(_ sender: Any?) { NotificationCenter.default.post(name: .findOpen, object: nil) }
    @objc func next(_ sender: Any?) { NotificationCenter.default.post(name: .findNext, object: nil) }
    @objc func previous(_ sender: Any?) { NotificationCenter.default.post(name: .findPrevious, object: nil) }

    /// Idempotent; SwiftUI may rebuild the menu, so call it whenever the editor appears.
    func arm() {
        guard let menu = NSApp.mainMenu else { return }
        walk(menu)
    }

    private func walk(_ menu: NSMenu) {
        for item in menu.items {
            if let sub = item.submenu { walk(sub) }
            let mods = item.keyEquivalentModifierMask
            guard mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { continue }
            switch (item.keyEquivalent, mods.contains(.shift)) {
            case ("f", false): retarget(item, #selector(open(_:)))
            case ("g", false): retarget(item, #selector(next(_:)))
            case ("g", true): retarget(item, #selector(previous(_:)))
            default: break
            }
        }
    }

    private func retarget(_ item: NSMenuItem, _ action: Selector) {
        item.target = self
        item.action = action
        item.isEnabled = true
    }
}
#endif
