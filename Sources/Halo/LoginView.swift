import SwiftUI
import WebKit

struct LoginSheetView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var latestCookies: [HTTPCookie] = []
    @State private var statusMessage = "请在下方网页完成知乎登录，然后点击“验证登录”。"
    @State private var isVerifying = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("知乎登录")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LoginWebView { cookies in
                latestCookies = cookies
            }
            .frame(minHeight: 460)

            HStack {
                Button("验证登录") {
                    Task {
                        isVerifying = true
                        let err = await state.completeLogin(with: latestCookies)
                        isVerifying = false
                        if let err {
                            statusMessage = err
                        } else {
                            statusMessage = "登录成功：\(state.username)"
                            dismiss()
                        }
                    }
                }
                .disabled(isVerifying)

                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minWidth: 900, minHeight: 620)
    }
}

private struct LoginWebView: NSViewRepresentable {
    let onCookiesUpdate: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesUpdate: onCookiesUpdate)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        if let url = URL(string: "https://www.zhihu.com/signin") {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookiesUpdate: ([HTTPCookie]) -> Void

        init(onCookiesUpdate: @escaping ([HTTPCookie]) -> Void) {
            self.onCookiesUpdate = onCookiesUpdate
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let filtered = cookies.filter { cookie in
                    cookie.domain.contains("zhihu.com") || cookie.domain.contains(".zhihu.com")
                }
                self.onCookiesUpdate(filtered)
            }
        }
    }
}
