#if os(iOS)
import SwiftUI
import UIKit

/// Shares the focused block id from the SwiftUI editor to the UIKit key-command
/// layer (they live on opposite sides of the hosting boundary).
final class EditorFocus: ObservableObject {
    @Published var id: UUID?
}

/// Wraps the editor so a hardware **Tab** cycles the focused block's type instead
/// of moving keyboard focus. iPadOS reserves Tab for focus traversal and
/// consumes it before SwiftUI's `.onKeyPress` runs; a `UIKeyCommand` with
/// `wantsPriorityOverSystemBehavior` overrides that. (macOS uses TabKeyMonitor.)
struct KeyCommandHost<Content: View>: UIViewControllerRepresentable {
    var onTab: () -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> KeyCommandHostVC {
        let vc = KeyCommandHostVC()
        vc.onTab = onTab
        vc.setRoot(AnyView(content()))
        return vc
    }

    func updateUIViewController(_ vc: KeyCommandHostVC, context: Context) {
        vc.onTab = onTab
        vc.setRoot(AnyView(content()))
    }
}

/// Non-generic so `#selector` and the Obj-C key-command machinery compile cleanly.
final class KeyCommandHostVC: UIViewController {
    var onTab: (() -> Void)?
    private var hosting: UIHostingController<AnyView>?

    func setRoot(_ view: AnyView) {
        if let h = hosting { h.rootView = view; return }
        let h = UIHostingController(rootView: view)
        h.view.backgroundColor = .clear
        h.view.frame = self.view.bounds
        h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(h)
        self.view.addSubview(h.view)
        h.didMove(toParent: self)
        hosting = h
    }

    override var keyCommands: [UIKeyCommand]? {
        let tab = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab))
        tab.wantsPriorityOverSystemBehavior = true
        return [tab]
    }

    @objc private func handleTab() { onTab?() }
}
#endif
