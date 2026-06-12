import SwiftUI
import WebKit

struct WeReadShelfView: View {
    @ObservedObject var state: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)
    ]

    var body: some View {
        Group {
            if state.weReadIsLoading {
                VStack {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                }
            } else if state.weReadBooks.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text("书架空空如也")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Button("刷新") {
                        Task { await state.fetchWeReadShelf() }
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sortedBooks) { book in
                            WeReadBookCard(book: book) {
                                state.openWeReadBook(book)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var sortedBooks: [WeReadBook] {
        state.weReadBooks.sorted { ($0.readUpdateTime ?? 0) > ($1.readUpdateTime ?? 0) }
    }
}

private struct WeReadBookCard: View {
    let book: WeReadBook
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                AsyncImage(url: book.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "book")
                                    .foregroundColor(.secondary)
                            )
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .overlay(ProgressView())
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Text(book.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct WeReadReaderView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Chapter title bar (hidden in quiet mode)
            if !state.weReadQuietMode {
                if state.weReadCatalog.indices.contains(state.weReadCurrentChapterIdx) {
                    HStack {
                        Text(state.weReadCatalog[state.weReadCurrentChapterIdx].title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(state.weReadCurrentChapterIdx + 1)/\(state.weReadCatalog.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                Divider()
            }

            // Content
            Group {
                if state.weReadIsLoading {
                    VStack {
                        Spacer()
                        ProgressView("加载中...")
                        Spacer()
                    }
                } else if let content = state.weReadChapterContent {
                    WeReadContentView(content: content, textScale: state.userZoomScale)
                } else {
                    VStack {
                        Spacer()
                        Text("暂无内容")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            // Bottom navigation (hidden in quiet mode)
            if !state.weReadQuietMode {
                Divider()
                HStack(spacing: 16) {
                    Button {
                        state.weReadShowCatalog = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.bordered)
                    .help("目录")

                    Spacer()

                    Button {
                        state.weReadMoveChapter(step: -1)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("上一章")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.weReadCurrentChapterIdx <= 0)

                    Button {
                        state.weReadMoveChapter(step: 1)
                    } label: {
                        HStack(spacing: 4) {
                            Text("下一章")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.weReadCurrentChapterIdx >= state.weReadCatalog.count - 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .sheet(isPresented: $state.weReadShowCatalog) {
            WeReadCatalogSheet(state: state)
        }
    }
}

private struct WeReadCatalogSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("目录")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(state.weReadCatalog.enumerated()), id: \.element.id) { idx, chapter in
                        Button {
                            Task { await state.loadWeReadChapter(idx: idx) }
                            dismiss()
                        } label: {
                            HStack {
                                Text(chapter.title)
                                    .foregroundColor(state.weReadCurrentChapterIdx == idx ? .accentColor : .primary)
                                    .font(.system(size: state.weReadCurrentChapterIdx == idx ? 14 : 13, weight: state.weReadCurrentChapterIdx == idx ? .semibold : .regular))
                                Spacer()
                                if state.weReadCurrentChapterIdx == idx {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .id(idx)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    proxy.scrollTo(state.weReadCurrentChapterIdx, anchor: .center)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 400)
    }
}

struct WeReadContentView: View {
    let content: WeReadChapterContent
    var textScale: CGFloat = 1.0

    var body: some View {
        WeReadHTMLWebView(html: processedHTML, style: content.style, textScale: textScale)
    }

    private var processedHTML: String {
        if content.format == "txt" {
            let paragraphs = content.html
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return paragraphs.map { "<p>\($0)</p>" }.joined()
        }
        var html = content.html
        html = html.replacingOccurrences(of: #"<\?xml.*\?>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<!DOCTYPE.*?>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<html[^>]*>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"</html>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<head[^>]*>[\s\S]*</head>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<body[^>]*>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"</body>"#, with: "", options: .regularExpression)
        return html
    }
}

struct WeReadHTMLWebView: NSViewRepresentable {
    let html: String
    let style: String
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
        context.coordinator.webView = view
        context.coordinator.startObservingScroll()
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let newID = "\(html.hashValue)_\(style.hashValue)_\(textScale)"
        if context.coordinator.lastLoadedID == newID { return }

        let bodyFontSize = max(12, 17 * textScale)
        let fullHTML = """
        <html>
        <head>
            <meta charset="utf-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <style>
                body {
                    font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
                    font-size: \(bodyFontSize)px;
                    line-height: 1.8;
                    color: #333;
                    margin: 0;
                    padding: 16px 24px;
                    max-width: 800px;
                    margin: 0 auto;
                }
                p { margin: 0.8em 0; text-indent: 2em; }
                img { max-width: 80%; height: auto; display: block; margin: 12px auto; border-radius: 6px; }
                h1, h2, h3, h4, h5, h6 { margin: 1.2em 0 0.6em; line-height: 1.4; }
                blockquote { border-left: 3px solid #ccc; margin: 12px 0; padding: 8px 16px; color: #666; background: #f9f9f9; border-radius: 4px; }
                pre { white-space: pre-wrap; background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; }
                a { color: #2563eb; text-decoration: none; }
                ::-webkit-scrollbar { width: 8px; height: 8px; }
                ::-webkit-scrollbar-track { background: #eceff3; border-radius: 8px; }
                ::-webkit-scrollbar-thumb { background: #9ca3af; border-radius: 8px; }
                \(style)
            </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        context.coordinator.lastLoadedID = newID
        nsView.loadHTMLString(fullHTML, baseURL: URL(string: "https://weread.qq.com"))
    }

    class Coordinator {
        var lastLoadedID: String?
        weak var webView: WKWebView?
        private var scrollObserver: Any?

        func startObservingScroll() {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: .weReadScroll,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let webView = self.webView else { return }
                let direction = note.userInfo?["direction"] as? String ?? "down"
                let js = direction == "up"
                    ? "window.scrollBy({top: -window.innerHeight * 0.75, behavior: 'instant'})"
                    : "window.scrollBy({top: window.innerHeight * 0.75, behavior: 'instant'})"
                webView.evaluateJavaScript(js)
            }
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }
    }
}

extension Notification.Name {
    static let weReadScroll = Notification.Name("weReadScroll")
}
