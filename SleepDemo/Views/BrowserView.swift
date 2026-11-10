import SwiftUI
import WebKit

/// 측정을 유지한 채 웹을 쓰기 위한 탭. 앱이 화면에 떠 있으므로 센서 기록이 계속된다.
struct BrowserView: View {
    @Environment(MeasurementController.self) private var controller
    @State private var web = WebModel()
    @State private var address = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { web.view.goBack() } label: { Image(systemName: "chevron.left") }
                Button { web.view.goForward() } label: { Image(systemName: "chevron.right") }
                TextField("주소 또는 검색어", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { web.open(address) }
                Button { web.view.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
            .padding(.horizontal)
            if controller.isMeasuring {
                UserStatePicker().padding(.horizontal)
            }
            WebView(view: web.view)
        }
        .padding(.top, 4)
        .onChange(of: web.currentURL) { _, url in address = url }
        .onAppear { if web.view.url == nil { web.open(WebModel.home) } }
    }
}

@Observable @MainActor
final class WebModel {
    static let home = "https://www.google.com"

    let view: WKWebView
    private(set) var currentURL = ""
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        observation = view.observe(\.url) { [weak self] v, _ in
            let url = v.url?.absoluteString ?? ""
            MainActor.assumeIsolated { self?.currentURL = url }
        }
    }

    /// 주소처럼 보이면 열고, 아니면 검색한다.
    func open(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        let url: URL?
        if s.contains("://") {
            url = URL(string: s)
        } else if s.contains("."), !s.contains(" ") {
            url = URL(string: "https://\(s)")
        } else {
            var c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: s)]
            url = c?.url
        }
        if let url { view.load(URLRequest(url: url)) }
    }
}

private struct WebView: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
