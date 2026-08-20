import SwiftUI
import UIKit

/// Pins the iOS 26 floating tab-bar platter to the leading edge.
/// System default centers the capsule when there is no search tab.
struct TabBarLeadingAligner: UIViewRepresentable {
    func makeUIView(context: Context) -> SentinelView {
        SentinelView()
    }

    func updateUIView(_ uiView: SentinelView, context: Context) {}

    final class SentinelView: UIView {
        private let pinView = PinView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }

        private func attach() {
            guard let tabBar = findTabBar() else { return }
            if pinView.superview !== tabBar {
                pinView.isUserInteractionEnabled = false
                pinView.backgroundColor = .clear
                pinView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                pinView.frame = tabBar.bounds
                tabBar.addSubview(pinView)
            }
            pinView.pinPlatter(in: tabBar)
        }

        private func findTabBar() -> UITabBar? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let tabBar = controller.tabBarController?.tabBar {
                    return tabBar
                }
                responder = current.next
            }
            return nil
        }
    }

    final class PinView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            if let tabBar = superview as? UITabBar {
                pinPlatter(in: tabBar)
            }
        }

        func pinPlatter(in tabBar: UITabBar) {
            let inset = max(tabBar.safeAreaInsets.left, 16)
            guard let platter = findPlatter(in: tabBar) else { return }
            if abs(platter.frame.minX - inset) > 0.5 {
                platter.frame.origin.x = inset
            }
        }

        private func findPlatter(in root: UIView) -> UIView? {
            let typeName = String(describing: type(of: root))
            if typeName.contains("Platter"), root.bounds.width > 0 {
                return root
            }
            for child in root.subviews {
                if let found = findPlatter(in: child) {
                    return found
                }
            }
            return nil
        }
    }
}
