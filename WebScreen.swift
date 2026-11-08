import SwiftUI
import WebKit
import UIKit

// MARK: - 错误信息

struct WebError: Identifiable {
    let id = UUID()
    let url: String
    let reason: String
}

// MARK: - 网页视图（UIKit 桥接）

struct WebView: UIViewRepresentable {
    let site: Site
    let incognito: Bool
    let store: AppStore
    @Binding var progress: Double
    @Binding var loading: Bool
    @Binding var error: WebError?
    @Binding var webView: WKWebView?
    @Binding var toast: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()

        // 1) Capacitor 垫片：让网页退回纯 Web 模式（用 IndexedDB/localStorage 持久化，跨更新稳定）
        cc.addUserScript(WKUserScript(source: Self.capacitorShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // 2) 控制台转发到原生日志（供调试面板）
        cc.addUserScript(WKUserScript(source: Self.consoleShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // 3) window.XingyujiNative JS 桥
        cc.addUserScript(WKUserScript(source: Self.bridgeShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        cc.add(context.coordinator, name: "native")
        config.userContentController = cc

        // 无痕：非持久化数据存储，退出即清，真隔离
        if incognito {
            config.websiteDataStore = .nonPersistent()
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        let bg = UIColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1)
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
        wv.isOpaque = false

        DispatchQueue.main.async {
            self.webView = wv
        }

        if let url = URL(string: site.url) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: 注入脚本

    static let capacitorShim = """
    (function(){
      window.Capacitor = window.Capacitor || {
        isNativePlatform: function(){ return false; },
        getPlatform: function(){ return "web"; },
        Plugins: {}
      };
      var d = document.documentElement;
      if (d) {
        d.style.setProperty("--apk-status-bar-h", "env(safe-area-inset-top, 0px)");
        d.style.setProperty("--apk-nav-bar-h", "env(safe-area-inset-bottom, 0px)");
      }
    })();
    """

    static let consoleShim = """
    (function(){
      function send(level, args){
        try {
          var parts = [];
          for (var i = 0; i < args.length; i++) {
            var a = args[i];
            if (a === null || a === undefined) { parts.push(String(a)); continue; }
            if (typeof a === "object") { try { parts.push(JSON.stringify(a)); } catch(e){ parts.push(String(a)); } }
            else { parts.push(String(a)); }
          }
          window.webkit.messageHandlers.native.postMessage({ id: "console", method: "log", args: [level, parts.join(" ")] });
        } catch(e) {}
      }
      ["log","warn","error","info"].forEach(function(k){
        var orig = console[k];
        console[k] = function(){ send(k, arguments); if (orig) { try { orig.apply(console, arguments); } catch(e){} } };
      });
    })();
    """

    static let bridgeShim = """
    (function(){
      window.__xynSeq = 0;
      window.__xynPending = {};
      window.__xynResolve = function(id, result){
        var f = window.__xynPending[id];
        if (f) { f(result); delete window.__xynPending[id]; }
      };
      function call(method, args){
        var id = "n" + (++window.__xynSeq);
        return new Promise(function(resolve){
          window.__xynPending[id] = resolve;
          window.webkit.messageHandlers.native.postMessage({ id: id, method: method, args: args });
        });
      }
      window.XingyujiNative = {
        notify: function(t,b){ call("notify",[t,b]); },
        toast: function(m){ call("toast",[m]); },
        reload: function(){ call("reload",[]); },
        clearCache: function(){ call("clearCache",[]); },
        openWeb: function(u){ call("openWeb",[u]); },
        log: function(t,m){ call("log",[t,m]); },
        getUrl: function(){ return call("getUrl",[]); },
        getSiteName: function(){ return call("getSiteName",[]); },
        getState: function(){ return call("getState",[]); },
        saveServer: function(i,n,u){ return call("saveServer",[i,n,u]); },
        deleteServer: function(i){ return call("deleteServer",[i]); },
        clearServerData: function(i){ return call("clearServerData",[i]); },
        setActiveServer: function(i){ return call("setActiveServer",[i]); }
      };
    })();
    """

    // MARK: Coordinator（导航 / 认证 / JS 桥）

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView

        init(_ p: WebView) { parent = p }

        // MARK: 导航

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
            parent.progress = 0
            parent.error = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.progress = 1
            parent.store.log("load", "完成 \(webView.url?.absoluteString ?? "")")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            parent.loading = false
            let url = webView.url?.absoluteString ?? parent.site.url
            parent.store.log("net-error", "\(url) -> \(ns.localizedDescription) (\(ns.code))")
            parent.error = WebError(url: url, reason: "\(ns.localizedDescription) (\(ns.code))")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            parent.loading = false
            parent.store.log("net-error", "\(webView.url?.absoluteString ?? "") -> \(ns.localizedDescription) (\(ns.code))")
        }

        // MARK: 导航策略：非 http(s) 交给系统（tel/mailto 等）

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased() {
                if scheme != "http" && scheme != "https" && scheme != "file" && scheme != "about" {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        // MARK: 新窗口（target=_blank）→ 当前页加载

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: 证书 / Basic Auth（等同安卓：放行自签 + 按 host 存凭证）

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
               challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {
                let host = challenge.protectionSpace.host
                if let (u, p) = AuthStore.get(host) {
                    completionHandler(.useCredential, URLCredential(user: u, password: p, persistence: .forSession))
                    return
                }
                DispatchQueue.main.async {
                    self.promptCredentials(host: host, realm: challenge.protectionSpace.realm) { u, p in
                        if let u, let p {
                            AuthStore.save(host, u, p)
                            completionHandler(.useCredential, URLCredential(user: u, password: p, persistence: .forSession))
                        } else {
                            completionHandler(.cancelAuthenticationChallenge, nil)
                        }
                    }
                }
                return
            }
            completionHandler(.performDefaultHandling, nil)
        }

        // MARK: 麦克风 / 相机（网页语音输入）

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // MARK: JS alert / confirm / prompt

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            showAlert(title: "提示", message: message, buttons: [("好", .cancel, completionHandler)])
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            showAlert(title: "确认", message: message, buttons: [
                ("取消", .cancel, { completionHandler(false) }),
                ("确定", .default, { completionHandler(true) })
            ])
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            topViewController()?.present(alert, animated: true)
        }

        // MARK: JS 桥消息

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let id = body["id"] as? String,
                  let method = body["method"] as? String else { return }
            let args = (body["args"] as? [Any]) ?? []
            let result = handle(method, args, message.webView)
            if id != "console" {
                resolve(id: id, result: result, in: message.webView)
            }
        }

        func handle(_ method: String, _ args: [Any], _ webView: WKWebView?) -> Any? {
            let store = parent.store
            switch method {
            case "log":
                let tag = args.first.flatMap { $0 as? String } ?? "js"
                let msg = args.count > 1 ? String(describing: args[1]) : ""
                store.log(tag, msg)
                return true
            case "toast", "notify":
                let msg = args.count > 1 ? String(describing: args[1]) : (args.first.flatMap { $0 as? String } ?? "")
                parent.toast = msg
                return true
            case "reload":
                webView?.reload()
                return true
            case "clearCache":
                Task { await WebDataClearer.clearAll() }
                return true
            case "openWeb":
                if let u = args.first.flatMap({ $0 as? String }), let url = URL(string: u) {
                    UIApplication.shared.open(url)
                }
                return true
            case "getUrl":
                return parent.site.url
            case "getSiteName":
                return parent.site.displayName
            case "getState":
                return store.stateJSON(site: parent.site)
            case "saveServer":
                if parent.incognito { return "" }
                let id = args.count > 0 ? (args[0] as? String) : nil
                let name = args.count > 1 ? String(describing: args[1]) : ""
                let url = args.count > 2 ? String(describing: args[2]) : ""
                return store.saveSite(id: id, name: name, url: url)?.id ?? ""
            case "deleteServer":
                if parent.incognito { return false }
                if let id = args.first as? String { store.deleteSite(id); return true }
                return false
            case "clearServerData":
                if parent.incognito { return false }
                if let id = args.first as? String,
                   let s = store.sites.first(where: { $0.id == id }) {
                    Task { await WebDataClearer.clear(host: s.host) }
                    return true
                }
                return false
            case "setActiveServer":
                if parent.incognito { return false }
                if let id = args.first as? String { store.setActive(id); return true }
                return false
            default:
                return nil
            }
        }

        func resolve(id: String, result: Any?, in webView: WKWebView?) {
            let lit = jsonLiteral(result)
            let js = "window.__xynResolve && window.__xynResolve('\(id)', \(lit))"
            webView?.evaluateJavaScript(js)
        }

        func jsonLiteral(_ v: Any?) -> String {
            guard let v else { return "null" }
            if let s = v as? String,
               let d = try? JSONSerialization.data(withJSONObject: s),
               let str = String(data: d, encoding: .utf8) {
                return str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let b = v as? Bool { return b ? "true" : "false" }
            if JSONSerialization.isValidJSONObject(v),
               let d = try? JSONSerialization.data(withJSONObject: v),
               let str = String(data: d, encoding: .utf8) {
                return str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "null"
        }

        // MARK: 辅助：弹窗

        private func showAlert(title: String, message: String, buttons: [(String, UIAlertAction.Style, () -> Void)]) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            for (t, style, action) in buttons {
                alert.addAction(UIAlertAction(title: t, style: style) { _ in action() })
            }
            topViewController()?.present(alert, animated: true)
        }

        private func promptCredentials(host: String, realm: String, completion: @escaping (String?, String?) -> Void) {
            let alert = UIAlertController(title: "需要登录", message: "\(host)\(realm.isEmpty ? "" : "（\(realm)）")\n请输入账号密码", preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "账号"; $0.autocapitalizationType = .none }
            alert.addTextField { $0.placeholder = "密码"; $0.isSecureTextEntry = true }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(nil, nil) })
            alert.addAction(UIAlertAction(title: "登录", style: .default) { _ in
                completion(alert.textFields?.first?.text ?? "", alert.textFields?.last?.text ?? "")
            })
            topViewController()?.present(alert, animated: true)
        }

        private func topViewController() -> UIViewController? {
            for scene in UIApplication.shared.connectedScenes {
                if let ws = scene as? UIWindowScene {
                    for w in ws.windows where w.isKeyWindow {
                        var vc: UIViewController? = w.rootViewController
                        while let p = vc?.presentedViewController { vc = p }
                        return vc
                    }
                }
            }
            return nil
        }
    }
}

// MARK: - 网页主界面（含悬浮按钮 / 错误页 / 调试面板）

struct WebScreen: View {
    let site: Site
    let incognito: Bool
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double = 0
    @State private var loading = true
    @State private var error: WebError?
    @State private var webView: WKWebView?
    @State private var toast: String?
    @State private var showDebug = false
    @State private var dbgDrag = CGSize.zero
    @State private var backDrag = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.055, green: 0.055, blue: 0.063).ignoresSafeArea()

                WebView(site: site, incognito: incognito, store: store,
                        progress: $progress, loading: $loading, error: $error,
                        webView: $webView, toast: $toast)
                    .ignoresSafeArea()

                if loading && error == nil {
                    loadingHint
                }
                if let error {
                    ErrorView(error: error,
                              onRetry: { webView?.reload() },
                              onBack: { dismiss() })
                }
                if store.debugBtn {
                    debugButton(geo)
                }
                if store.backBtn {
                    backButton(geo)
                }
                if incognito {
                    badge
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(text: toast)
            }
        }
        .sheet(isPresented: $showDebug) {
            DebugSheet()
        }
        .onChange(of: toast) { _, newValue in
            if newValue != nil {
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    toast = nil
                }
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    // MARK: 悬浮按钮

    private func debugButton(_ geo: GeometryProxy) -> some View {
        let base = CGPoint(
            x: store.debugBtnX >= 0 ? store.debugBtnX : geo.size.width - 34,
            y: store.debugBtnY >= 0 ? store.debugBtnY : 70
        )
        return Text("🐞")
            .font(.title3)
            .padding(8)
            .background(.black.opacity(0.45))
            .clipShape(Circle())
            .position(x: base.x + dbgDrag.width, y: base.y + dbgDrag.height)
            .gesture(DragGesture()
                .onChanged { dbgDrag = $0.translation }
                .onEnded { v in
                    store.debugBtnX = clamp(base.x + v.translation.width, geo.size.width)
                    store.debugBtnY = clamp(base.y + v.translation.height, geo.size.height)
                    dbgDrag = .zero
                })
            .onTapGesture { showDebug = true }
    }

    private func backButton(_ geo: GeometryProxy) -> some View {
        let base = CGPoint(
            x: store.backBtnX >= 0 ? store.backBtnX : 30,
            y: store.backBtnY >= 0 ? store.backBtnY : geo.size.height - 48
        )
        return Text("‹")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45))
            .clipShape(Capsule())
            .position(x: base.x + backDrag.width, y: base.y + backDrag.height)
            .gesture(DragGesture()
                .onChanged { backDrag = $0.translation }
                .onEnded { v in
                    store.backBtnX = clamp(base.x + v.translation.width, geo.size.width)
                    store.backBtnY = clamp(base.y + v.translation.height, geo.size.height)
                    backDrag = .zero
                })
            .onTapGesture {
                if let wv = webView, wv.canGoBack {
                    wv.goBack()
                } else {
                    dismiss()
                }
            }
    }

    private func clamp(_ v: CGFloat, _ max: CGFloat) -> Double {
        Double(min(max(20, v), max - 20))
    }

    private var loadingHint: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("正在加载…\n首次打开需要下载较多资源，请耐心等待")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var badge: some View {
        Text("🕶 无痕")
            .font(.caption2)
            .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 1.0))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 0.13, green: 0.09, blue: 0.19).opacity(0.8))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 52)
            .padding(.leading, 16)
    }
}

// MARK: - 错误页

struct ErrorView: View {
    let error: WebError
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("⚠️").font(.system(size: 46))
            Text("打不开这个网址").font(.title3)
            Text(error.reason).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(error.url).font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button(action: onRetry) {
                Text("重新连接")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Button(action: onBack) {
                Text("返回站点列表")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.3))
                    .foregroundStyle(Color(white: 0.8))
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}

// MARK: - 提示条

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .clipShape(Capsule())
            .padding(.top, 54)
    }
}

// MARK: - 调试面板

struct DebugSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if store.logs.isEmpty {
                        Text("暂无日志").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .onAppear {
                            proxy.scrollTo(store.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("上传") { upload() }
                    Button("清空") { store.logs.removeAll() }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { result != nil },
                set: { if !$0 { result = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(result ?? "")
            }
        }
    }

    private func upload() {
        let content = store.logs.joined(separator: "\n")
        Task {
            result = await LogUploader.upload(content)
        }
    }
}
