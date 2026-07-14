#if os(macOS)
import AppKit

/// Makes the Tab key cycle the focused block's type instead of moving keyboard
/// focus to the next field.
///
/// AppKit's field editor treats Tab as "advance to the next key view", and it
/// consumes the key before SwiftUI's `.onKeyPress` handler on a focused
/// `TextField` ever runs — so Tab silently moved focus instead of changing the
/// block type. A local key-down monitor sees the event first and can consume it.
final class TabKeyMonitor: ObservableObject {
    /// id of the block currently being edited (nil = not in a block field).
    var focusedID: UUID?
    /// Invoked with the focused id when plain Tab is pressed inside a block.
    var onCycle: ((UUID) -> Void)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // keyCode 48 = Tab. Only plain Tab (no modifiers) while a block is focused;
            // Shift-Tab and everything else keep their normal behaviour.
            let mods = event.modifierFlags.intersection([.shift, .command, .option, .control, .function])
            if event.keyCode == 48, mods.isEmpty, let id = self.focusedID {
                self.onCycle?(id)
                return nil // consume — don't let focus traverse
            }
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    deinit { stop() }
}
#endif
