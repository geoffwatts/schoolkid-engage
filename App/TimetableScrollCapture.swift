import SwiftUI

/// Keeps the existing native list scroll view so date navigation can preserve its position.
struct TimetableScrollCapture: UIViewRepresentable {
    var resolve: (UIScrollView) -> Void
    final class Probe: UIView {
        var resolve: ((UIScrollView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var parent = self.superview
                while let current = parent {
                    if let scroll = current as? UIScrollView { self.resolve?(scroll); return }
                    parent = current.superview
                }
            }
        }
    }
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.isUserInteractionEnabled = false; view.resolve = resolve; return view }
    func updateUIView(_ view: Probe, context: Context) { view.resolve = resolve }
}
