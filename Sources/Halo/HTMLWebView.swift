import SwiftUI
import WebKit

struct HTMLWebView: NSViewRepresentable {
    let html: String
    var textScale: CGFloat = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        if let scrollView = view.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = false
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // 内容没变就不重新加载，避免 WebView 白屏闪烁
        let newID = contentIdentifier(html: html, textScale: textScale)
        if context.coordinator.lastLoadedID == newID { return }

        let bodyFontSize = max(12, 16 * textScale)
        let normalizedHTML = normalizeImageSources(in: html)
        let content = """
        <html>
        <head>
            <meta charset="utf-8"/>
            <meta name="referrer" content="no-referrer-when-downgrade"/>
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
                img:hover { box-shadow: 0 4px 20px rgba(0,0,0,0.15) !important; }
                #img-preview-overlay { display: none; position: fixed; inset: 0; z-index: 99999; background: rgba(0,0,0,0.85); cursor: zoom-out; justify-content: center; align-items: center; }
                #img-preview-overlay.active { display: flex; }
                #img-preview-overlay img { max-width: 90vw; max-height: 90vh; width: auto; height: auto; border-radius: 8px; cursor: zoom-out; }
                pre { white-space: pre-wrap; background: #f3f4f6; padding: 10px; border-radius: 6px; overflow-x: auto; }
                blockquote { border-left: 3px solid #4b5563; margin: 10px 0; padding: 8px 12px; color: #374151; background: #f3f4f6; border-radius: 6px; }
                a { color: #2563eb; text-decoration: none; }
                html, body { }
                ::-webkit-scrollbar { width: 8px; height: 8px; }
                ::-webkit-scrollbar-track { background: #eceff3; border-radius: 8px; }
                ::-webkit-scrollbar-thumb { background: #9ca3af; border-radius: 8px; }
            </style>
            <script>
                document.addEventListener('DOMContentLoaded', function () {
                    // 创建预览浮层
                    var overlay = document.createElement('div');
                    overlay.id = 'img-preview-overlay';
                    var previewImg = document.createElement('img');
                    overlay.appendChild(previewImg);
                    document.body.appendChild(overlay);

                    overlay.addEventListener('click', function () {
                        overlay.classList.remove('active');
                    });

                    function fixSrc(img) {
                        // 优先用 src（通常是大图），data 属性多为缩略图
                        var real = img.getAttribute('src')
                            || img.getAttribute('data-original')
                            || img.getAttribute('data-actualsrc')
                            || img.getAttribute('data-src')
                            || img.getAttribute('data-default-watermark-src');
                        if (!real) return null;
                        if (real.startsWith('//')) real = 'https:' + real;
                        return real;
                    }

                    // 处理所有图片
                    var imgs = document.querySelectorAll('img');
                    imgs.forEach(function (img) {
                        var real = fixSrc(img);
                        if (!real) return;
                        img.setAttribute('src', real);
                        img.setAttribute('loading', 'eager');
                        // 清除属性
                        img.removeAttribute('width');
                        img.removeAttribute('height');
                        img.removeAttribute('data-size');
                        img.removeAttribute('data-rawwidth');
                        img.removeAttribute('data-rawheight');
                        // 用 JS 强制设置尺寸，覆盖所有 CSS/内联样式
                        img.style.setProperty('max-width', '40%', 'important');
                        img.style.setProperty('width', 'auto', 'important');
                        img.style.setProperty('height', 'auto', 'important');
                        img.style.setProperty('display', 'block', 'important');
                        img.style.setProperty('border-radius', '6px', 'important');
                        img.style.setProperty('cursor', 'zoom-in', 'important');
                        // 清除父元素的固定尺寸
                        var parent = img.parentElement;
                        if (parent) {
                            parent.style.setProperty('width', 'auto', 'important');
                            parent.style.setProperty('max-width', '40%', 'important');
                        }
                        if (img.classList.contains('origin_image')) {
                            img.classList.remove('origin_image');
                        }
                        img.addEventListener('click', function (e) {
                            e.stopPropagation();
                            previewImg.src = img.getAttribute('data-full-src') || real;
                            previewImg.style.setProperty('max-width', '90vw', 'important');
                            previewImg.style.setProperty('max-height', '90vh', 'important');
                            previewImg.style.setProperty('width', 'auto', 'important');
                            previewImg.style.setProperty('height', 'auto', 'important');
                            overlay.classList.add('active');
                        });
                    });

                    // 处理 noscript 中的图片
                    var noscripts = document.querySelectorAll('noscript');
                    noscripts.forEach(function (ns) {
                        var div = document.createElement('div');
                        div.innerHTML = ns.textContent || ns.innerHTML;
                        var nestedImgs = div.querySelectorAll('img');
                        nestedImgs.forEach(function (img) {
                            var real = fixSrc(img);
                            if (!real) return;
                            img.setAttribute('src', real);
                            img.setAttribute('loading', 'eager');
                            img.removeAttribute('width');
                            img.removeAttribute('height');
                            img.style.width = 'auto';
                            img.style.height = 'auto';
                            img.addEventListener('click', function (e) {
                                e.stopPropagation();
                                previewImg.src = img.getAttribute('data-full-src') || real;
                                overlay.classList.add('active');
                            });
                            ns.parentNode.insertBefore(img, ns);
                        });
                        ns.remove();
                    });
                });
            </script>
        </head>
        <body>\(normalizedHTML)</body>
        </html>
        """
        context.coordinator.lastLoadedID = newID
        nsView.loadHTMLString(content, baseURL: URL(string: "https://www.zhihu.com"))
    }

    private func contentIdentifier(html: String, textScale: CGFloat) -> String {
        "\(html.hashValue)_\(textScale)"
    }

    class Coordinator {
        var lastLoadedID: String?
    }

    private func normalizeImageSources(in html: String) -> String {
        var output = html

        // 处理 <noscript> 中的图片：知乎会把一些图片放在 <noscript> 里作为 fallback，
        // 把它们提取出来并移除 <noscript> 标签
        let noscriptPattern = #"<noscript\b[^>]*>(.*?)</noscript>"#
        if let regex = try? NSRegularExpression(pattern: noscriptPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: output.utf16.count)
            let matches = regex.matches(in: output, options: [], range: range).reversed()
            for match in matches {
                guard let matchRange = Range(match.range, in: output),
                      match.numberOfRanges >= 2,
                      let contentRange = Range(match.range(at: 1), in: output) else { continue }
                let innerContent = String(output[contentRange])
                // 提取 noscript 里的 img 标签，放到 noscript 外面
                output.replaceSubrange(matchRange, with: innerContent)
            }
        }

        // 处理 <img> 标签
        let pattern = #"<img\b[^>]*>"#
        let range = NSRange(location: 0, length: output.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return output
        }
        let matches = regex.matches(in: output, options: [], range: range).reversed()
        for match in matches {
            guard let matchRange = Range(match.range, in: output) else { continue }
            let tag = String(output[matchRange])
            let preferred = value(of: "data-original", in: tag)
                ?? value(of: "data-actualsrc", in: tag)
                ?? value(of: "data-src", in: tag)
                ?? value(of: "data-default-watermark-src", in: tag)
                ?? value(of: "src", in: tag)
            guard var src = preferred, !src.isEmpty else { continue }
            if src.hasPrefix("//") { src = "https:" + src }
            src = src.replacingOccurrences(of: "&amp;", with: "&")

            var injected = setOrReplace(attribute: "src", value: src, in: tag)
            injected = setOrReplace(attribute: "loading", value: "eager", in: injected)
            injected = setOrReplace(attribute: "data-full-src", value: src, in: injected)
            // 清除内联宽高属性
            injected = removeAttribute("width", in: injected)
            injected = removeAttribute("height", in: injected)
            injected = removeAttribute("data-size", in: injected)
            injected = removeAttribute("data-rawwidth", in: injected)
            injected = removeAttribute("data-rawheight", in: injected)
            // 清除 style 中的 width/height
            injected = removeStyleProperties(injected, properties: ["width", "height", "max-width", "max-height"])
            output.replaceSubrange(matchRange, with: injected)
        }
        return output
    }

    private func value(of attr: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: attr)
        // 支持双引号、单引号、无引号三种属性值写法
        let patterns: [String] = [
            #"\b"# + escaped + #"\s*=\s*"([^"]*)""#,
            #"\b"# + escaped + #"\s*=\s*'([^']*)'"#,
            #"\b"# + escaped + #"\s*=\s*([^\s>]+)"#
        ]
        let range = NSRange(location: 0, length: tag.utf16.count)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: tag, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: tag) else {
                continue
            }
            let val = String(tag[valueRange])
            if !val.isEmpty {
                return val
            }
        }
        return nil
    }

    private func setOrReplace(attribute: String, value: String, in tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: attribute)
        // 支持双引号和单引号
        let patterns: [String] = [
            #"\b"# + escaped + #"\s*=\s*"[^"]*""#,
            #"\b"# + escaped + #"\s*=\s*'[^']*'"#
        ]
        let range = NSRange(location: 0, length: tag.utf16.count)
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: tag, options: [], range: range) != nil {
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

    private func removeAttribute(_ attribute: String, in tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: attribute)
        let patterns: [String] = [
            #"\b"# + escaped + #"\s*=\s*"[^"]*""#,
            #"\b"# + escaped + #"\s*=\s*'[^']*'"#,
            #"\b"# + escaped + #"\s*=\s*[^\s>]+"#
        ]
        var result = tag
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result
    }

    private func removeStyleProperties(_ tag: String, properties: [String]) -> String {
        // 提取 style 属性值
        let stylePattern = #"\bstyle\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: stylePattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: tag.utf16.count)),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return tag
        }
        var style = String(tag[valueRange])
        for prop in properties {
            let propPattern = NSRegularExpression.escapedPattern(for: prop) + #"\s*:\s*[^;]+;?\s*"#
            if let propRegex = try? NSRegularExpression(pattern: propPattern, options: [.caseInsensitive]) {
                style = propRegex.stringByReplacingMatches(in: style, options: [], range: NSRange(location: 0, length: style.utf16.count), withTemplate: "")
            }
        }
        let trimmed = style.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // style 为空，移除整个 style 属性
            return removeAttribute("style", in: tag)
        }
        return setOrReplace(attribute: "style", value: trimmed, in: tag)
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
