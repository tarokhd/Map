import CoreLocation
import UIKit
import WebKit

final class WorldCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate {
    private weak var view: WKWebView?
    private var server: WorldServer?
    private let manager = CLLocationManager()
    private struct Request { let once: Bool; let timeout: Double; var timer: DispatchWorkItem? }
    private var pending: [Int: Request] = [:]
    private var observers: [NSObjectProtocol] = []
    private var active = true
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 1
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.active = true; self?.startLocations() })
    }
    func start(_ view: WKWebView) {
        self.view = view
        guard let directory = Bundle.main.url(forResource: "World", withExtension: nil) else { showError(); return }
        let server = WorldServer(directory: directory)
        self.server = server
        do {
            try server.start { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let url): self.view?.load(URLRequest(url: url))
                case .failure: self.showError()
                }
            }
        } catch { showError() }
    }
    private func showError() {
        view?.loadHTMLString("<html lang='fa' dir='rtl'><meta name='viewport' content='width=device-width'><body style='background:#09131d;color:#e6f0f2;font:18px system-ui;padding:40px'>راه‌اندازی برنامه ممکن نشد. برنامه را دوباره باز کنید.</body></html>", baseURL: nil)
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              WorldHostPolicy.trusted(message.frameInfo.request.url, origin: server?.origin),
              WorldHostPolicy.trusted(view?.url, origin: server?.origin),
              let body = message.body as? [String: Any], let raw = body["id"] as? String,
              let id = Int(raw), (1...1_000_000_000).contains(id) else { return }
        if body["action"] as? String == "cancel" {
            pending.removeValue(forKey: id)?.timer?.cancel()
            if pending.isEmpty { manager.stopUpdatingLocation() }
            return
        }
        guard body["action"] as? String == "request", let once = body["once"] as? Bool else { return }
        pending[id]?.timer?.cancel()
        pending[id] = Request(once: once, timeout: max(1, min(60, (body["timeout"] as? Double ?? 15000) / 1000)), timer: nil)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: startLocations()
        default: sendError(id, code: 1, message: "اجازه موقعیت داده نشد.", remove: true)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: startLocations()
        case .denied, .restricted:
            for id in Array(pending.keys) { sendError(id, code: 1, message: "اجازه موقعیت داده نشد.", remove: true) }
        default: break
        }
    }
    private func arm(_ id: Int) {
        guard var request = pending[id] else { return }
        request.timer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let request = self.pending[id] else { return }
            self.sendError(id, code: 3, message: "دریافت موقعیت بیش از حد طول کشید.", remove: request.once)
        }
        request.timer = work
        pending[id] = request
        DispatchQueue.main.asyncAfter(deadline: .now() + request.timeout, execute: work)
    }
    private func startLocations() {
        guard active, !pending.isEmpty, [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { return }
        for id in Array(pending.keys) { arm(id) }
        manager.startUpdatingLocation()
        if let position = manager.location, fresh(position) { publish(position) }
    }
    private func fresh(_ position: CLLocation) -> Bool {
        let age = -position.timestamp.timeIntervalSinceNow
        return CLLocationCoordinate2DIsValid(position.coordinate) && position.horizontalAccuracy >= 0 && position.horizontalAccuracy <= 65 && age >= 0 && age <= 15
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let position = locations.last { publish(position) }
    }
    private func publish(_ position: CLLocation) {
        guard active, CLLocationCoordinate2DIsValid(position.coordinate), position.horizontalAccuracy >= 0 else { return }
        let payload: [String: Any] = ["timestamp": position.timestamp.timeIntervalSince1970 * 1000, "coords": [
            "latitude": position.coordinate.latitude, "longitude": position.coordinate.longitude,
            "accuracy": position.horizontalAccuracy, "altitude": position.verticalAccuracy >= 0 ? position.altitude as Any : NSNull(),
            "altitudeAccuracy": position.verticalAccuracy >= 0 ? position.verticalAccuracy as Any : NSNull(),
            "heading": position.course >= 0 ? position.course as Any : NSNull(), "speed": position.speed >= 0 ? position.speed as Any : NSNull()]]
        for (id, request) in pending {
            if request.once && !fresh(position) { continue }
            if request.once { pending.removeValue(forKey: id)?.timer?.cancel() }
            else if fresh(position) { arm(id) }
            dispatch(id, position: payload, error: nil)
        }
        if pending.isEmpty { manager.stopUpdatingLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        for (id, request) in pending { sendError(id, code: denied ? 1 : 2, message: denied ? "اجازه موقعیت داده نشد." : "موقعیت فعلاً در دسترس نیست.", remove: denied || request.once) }
    }
    private func sendError(_ id: Int, code: Int, message: String, remove: Bool) {
        if remove { pending.removeValue(forKey: id)?.timer?.cancel() }
        dispatch(id, position: nil, error: ["code": code, "message": message])
        if pending.isEmpty { manager.stopUpdatingLocation() }
    }
    private func dispatch(_ id: Int, position: [String: Any]?, error: [String: Any]?) {
        guard WorldHostPolicy.trusted(view?.url, origin: server?.origin) else { return }
        let encode: ([String: Any]?) -> String = { object in
            guard let object = object, let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return "null" }
            return json
        }
        view?.evaluateJavaScript("window.__nativeLocation?.(\(id),\(encode(position)),\(encode(error)));", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if WorldHostPolicy.trusted(navigationAction.request.url, origin: server?.origin) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { cancel(); webView.reload() }
    private func pause() {
        active = false
        manager.stopUpdatingLocation()
        for id in Array(pending.keys) { pending[id]?.timer?.cancel(); pending[id]?.timer = nil }
    }
    private func cancel() {
        for request in pending.values { request.timer?.cancel() }
        pending.removeAll(); manager.stopUpdatingLocation()
    }
    func stop() {
        cancel(); server?.stop(); view = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
    deinit { stop() }
}
