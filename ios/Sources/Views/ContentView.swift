import SwiftUI
import WebKit

/// All product UI and navigation live in the same packaged World runtime as Android and Web.
struct ContentView: UIViewRepresentable {
    func makeCoordinator() -> WorldCoordinator { WorldCoordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "world")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 9/255, green: 19/255, blue: 29/255, alpha: 1)
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.start(view)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { }
    static func dismantleUIView(_ view: WKWebView, coordinator: WorldCoordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "world")
        coordinator.stop()
    }
}
