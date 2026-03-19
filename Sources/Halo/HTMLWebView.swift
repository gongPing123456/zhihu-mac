import SwiftUI
import WebKit

struct HTMLWebView: NSViewRepresentable {
    let html: String
    var textScale: CGFloat = 1.0

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        if let scrollView = view.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let bodyFontSize = max(12, 16 * textScale)
        let normalizedHTML = normalizeImageSources(in: html)
        let content = """
        <html>
        <head>
            <meta charset="utf-8"/>
            <meta name="referrer" content="no-referrer"/>
            <style>
                body { font-family: -apple-system; font-size: \(bodyFontSize)px; line-height: 1.7; color: #1f2937; margin: 0; padding: 0; }
                /* 强制覆盖知乎正文默认窄版容器，避免在某些窗口比例下看起来不铺满 */
                .RichContent,
                .RichContent-inner,
                .Post-RichTextContainer,
                .RichText,
                .RichText.ztext {
                    width: 100% !important;
                    max-width: none !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    box-sizing: border-box !important;
                }
                .RichText p,
                .RichText div {
                    max-width: none !important;
                }
                img { max-width: 100%; height: auto; border-radius: 8px; }
                pre { white-space: pre-wrap; background: #f3f4f6; padding: 10px; border-radius: 6px; overflow-x: auto; }
                blockquote { border-left: 3px solid #4b5563; margin: 10px 0; padding: 8px 12px; color: #374151; background: #f3f4f6; border-radius: 6px; }
                a { color: #2563eb; text-decoration: none; }
                html, body { scrollbar-width: none; -ms-overflow-style: none; }
                html::-webkit-scrollbar, body::-webkit-scrollbar { display: none; }
                ::-webkit-scrollbar { width: 8px; height: 8px; }
                ::-webkit-scrollbar-track { background: #eceff3; border-radius: 8px; }
                ::-webkit-scrollbar-thumb { background: #9ca3af; border-radius: 8px; }
            </style>
            <script>
                document.addEventListener('DOMContentLoaded', function () {
                    var imgs = document.querySelectorAll('img');
                    imgs.forEach(function (img) {
                        var real = img.getAttribute('data-original') || img.getAttribute('data-actualsrc') || img.getAttribute('data-src') || img.getAttribute('src');
                        if (!real) return;
                        if (real.startsWith('//')) real = 'https:' + real;
                        img.setAttribute('src', real);
                        img.setAttribute('referrerpolicy', 'no-referrer');
                        img.setAttribute('loading', 'eager');
                    });
                });
            </script>
        </head>
        <body>\(normalizedHTML)</body>
        </html>
        """
        nsView.loadHTMLString(content, baseURL: URL(string: "https://www.zhihu.com"))
    }

    private func normalizeImageSources(in html: String) -> String {
        let pattern = #"<img\b[^>]*>"#
        let range = NSRange(location: 0, length: html.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
        let matches = regex.matches(in: html, options: [], range: range).reversed()
        var output = html
        for match in matches {
            guard let matchRange = Range(match.range, in: output) else { continue }
            let tag = String(output[matchRange])
            let preferred = value(of: "data-original", in: tag)
                ?? value(of: "data-actualsrc", in: tag)
                ?? value(of: "data-src", in: tag)
                ?? value(of: "src", in: tag)
            guard var src = preferred, !src.isEmpty else { continue }
            if src.hasPrefix("//") { src = "https:" + src }
            src = src.replacingOccurrences(of: "&amp;", with: "&")

            var injected = setOrReplace(attribute: "src", value: src, in: tag)
            injected = setOrReplace(attribute: "referrerpolicy", value: "no-referrer", in: injected)
            injected = setOrReplace(attribute: "loading", value: "eager", in: injected)
            output.replaceSubrange(matchRange, with: injected)
        }
        return output
    }

    private func value(of attr: String, in tag: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: attr) + #"\s*=\s*"([^"]+)""#
        let range = NSRange(location: 0, length: tag.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

    private func setOrReplace(attribute: String, value: String, in tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: attribute)
        let pattern = #"\b"# + escaped + #"\s*=\s*"[^"]*""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: tag.utf16.count)
            if regex.firstMatch(in: tag, options: [], range: range) != nil {
                return regex.stringByReplacingMatches(
                    in: tag,
                    options: [],
                    range: range,
                    withTemplate: #"\#(attribute)="\#(value)""#
                )
            }
        }
        return tag.replacingOccurrences(of: ">", with: #" \#(attribute)="\#(value)">"#)
    }
}

struct URLWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
