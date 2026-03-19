import SwiftUI
import AppKit

@main
struct HaloApp: App {
    @StateObject private var state = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let iconURL = Bundle.main.url(forResource: "HaloIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("Halo") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 680, minHeight: 560)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .task {
                    await state.initialLoad()
                    state.ensureSelection()
                }
        }
        .defaultSize(width: 1280, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("缩放") {
                Button("缩小") { state.decreaseZoom() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("放大") { state.increaseZoom() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("还原") { state.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandMenu("翻页") {
                Button("上一个（←）") { state.moveSelection(step: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("下一个（→）") { state.moveSelection(step: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("上一个（A）") { state.moveSelection(step: -1) }
                    .keyboardShortcut("a", modifiers: [])
                Button("下一个（D）") { state.moveSelection(step: 1) }
                    .keyboardShortcut("d", modifiers: [])
            }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var showLoginSheet = false
    private let topTabs: [SidebarTab] = [.home, .hotList]

    var body: some View {
        ReaderWorkspace()
            .background(WindowConfigurator())
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    ForEach(topTabs) { tab in
                        Button {
                            state.selectedTab = tab
                            state.ensureSelection()
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: state.selectedTab == tab ? .semibold : .regular))
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .background(
                                    Capsule()
                                        .fill(state.selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                ToolbarItem(placement: .principal) {
                    if state.selectedTab == .hotList, let progress = state.selectionProgress() {
                        Text("\(progress.index)/\(progress.total)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(" ")
                            .font(.system(size: 12))
                            .foregroundStyle(.clear)
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button("上一页") { state.moveSelection(step: -1) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    Button("下一页") { state.moveSelection(step: 1) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)

                    if state.isLoggedIn {
                        HStack(spacing: 6) {
                            Text(state.username)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("退出") { state.logout() }
                                .controlSize(.small)
                        }
                    } else {
                        Button("登录") {
                            showLoginSheet = true
                        }
                        .controlSize(.small)
                    }
                }
            }
            .onChange(of: state.selectedTab) { _, _ in
                state.ensureSelection()
                if state.selectedTab == .hotList && state.hotListItems.isEmpty {
                    Task { await state.refreshHotList() }
                } else if state.selectedTab == .hotList {
                    Task { await state.ensureHotListDefaultLoaded() }
                }
                if state.selectedTab == .hotSearch {
                    Task { await state.ensureHotSearchDefaultLoaded() }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginSheetView()
                    .environmentObject(state)
            }
    }
}

private struct ReaderWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            DetailView()
        }
        .ignoresSafeArea(.container, edges: .top)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var statusStrip: some View {
        if let error = state.errorMessage, !error.isEmpty {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Divider()
        } else if state.isLoadingMoreHome && state.selectedTab == .home {
            Text("加载更多中...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Divider()
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from view: NSView) {
        guard let window = view.window ?? NSApp.keyWindow else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

private struct DetailView: View {
    @EnvironmentObject private var state: AppState
    private func z(_ size: CGFloat) -> CGFloat { size * state.userZoomScale }
    private var sectionLineColor: Color {
        Color(nsColor: NSColor(srgbRed: 234/255, green: 234/255, blue: 234/255, alpha: 1))
    }

    var body: some View {
        if state.selectedTab == .hotSearch {
            hotSearchPane
        } else if state.selectedTab == .hotList {
            hotListPane
        } else if let item = state.selectedItem {
            GeometryReader { proxy in
                let useSplit = proxy.size.width >= 920
                if useSplit {
                    HStack(spacing: 0) {
                        contentPane(item: item)
                            .frame(width: proxy.size.width * 0.64)
                        Divider()
                        commentsPane
                            .frame(width: proxy.size.width * 0.36)
                    }
                } else {
                    VStack(spacing: 0) {
                        contentPane(item: item)
                            .frame(maxHeight: .infinity)
                        Divider()
                        commentsPane
                            .frame(minHeight: 240, maxHeight: proxy.size.height * 0.42)
                    }
                }
            }
        } else {
            Text(emptyHint)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hotListPane: some View {
        GeometryReader { proxy in
            let widths = hotTwoColumnWidths(totalWidth: proxy.size.width)
            HStack(spacing: 0) {
                hotTopicPane
                    .frame(width: widths.left)
                Divider()
                hotCommentPane
                    .frame(width: widths.right)
            }
        }
    }

    private var hotTopicPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("热点")
                    .font(.headline)
                if state.hotListItems.isEmpty {
                    Text("暂无热榜，点击上方刷新")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(state.hotListItems) { topic in
                        Button {
                            Task { await state.loadHotListContents(questionID: topic.contentId) }
                        } label: {
                            Text(topic.title)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(state.selectedHotListQuestionID == topic.contentId ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var hotResultListPaneForHotList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("相关文章")
                    .font(.headline)
                Spacer()
                if state.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            Divider()

            List(state.hotListContentItems, selection: Binding(
                get: { state.selectedItem?.id },
                set: { newID in
                    let item = state.hotListContentItems.first { $0.id == newID }
                    state.select(item)
                })
            ) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(item.excerpt.isEmpty ? "暂无摘要" : item.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.authorName).lineLimit(1)
                        Text("👍 \(item.voteCount)")
                        Text("💬 \(item.commentCount)")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .tag(item.id)
            }
            .overlay {
                if state.hotListContentItems.isEmpty {
                    Text(state.isLoggedIn ? "先点左侧热点加载文章列表" : "该接口通常需要登录，请先点击上方“登录”")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hotSearchPane: some View {
        GeometryReader { proxy in
            let widths = hotTripleColumnWidths(totalWidth: proxy.size.width)
            HStack(spacing: 0) {
                hotKeywordPane
                    .frame(width: widths.left)
                Divider()
                hotResultListPane
                    .frame(width: widths.middle)
                Divider()
                hotCommentPane
                    .frame(width: widths.right)
            }
        }
    }

    private func hotTripleColumnWidths(totalWidth: CGFloat) -> (left: CGFloat, middle: CGFloat, right: CGFloat) {
        // 主体阅读优先：左窄（热搜词）+ 中窄（相关文章）+ 右宽（内容+评论）
        let left = max(160, min(220, totalWidth * 0.16))
        let middle = max(220, min(320, totalWidth * 0.24))
        let used = left + middle + 2 // two dividers
        let right = max(460, totalWidth - used)
        return (left, middle, right)
    }

    private func hotTwoColumnWidths(totalWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        // 热榜模式去掉中栏，只保留“热点 + 内容评论”
        // 以比例缩放为主，窗口缩小时两栏会一起等比收缩
        let leftRatio: CGFloat = 0.20
        let left = max(120, totalWidth * leftRatio)
        let right = max(260, totalWidth - left - 1) // one divider
        return (left, right)
    }

    private var hotKeywordPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if state.filteredHotSearchItems.isEmpty {
                    Text("暂无热搜，点击上方刷新重试")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(state.filteredHotSearchItems) { hot in
                        Button {
                            Task { await state.searchFromHotQuery(hot.query) }
                        } label: {
                            HStack {
                                Text(hot.query)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text(hot.hotDisplay)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(state.selectedHotSearchQuery == hot.query ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var hotResultListPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.activeSearchQuery == nil ? "文章+内容" : "文章+内容：\(state.activeSearchQuery!)")
                    .font(.headline)
                Spacer()
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)
            Divider()

            List(state.searchResultItems, selection: Binding(
                get: { state.selectedItem?.id },
                set: { newID in
                    let item = state.searchResultItems.first { $0.id == newID }
                    state.select(item)
                })
            ) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(item.excerpt.isEmpty ? "暂无摘要" : item.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.authorName).lineLimit(1)
                        Text("👍 \(item.voteCount)")
                        Text("💬 \(item.commentCount)")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .tag(item.id)
            }
            .overlay {
                if state.searchResultItems.isEmpty {
                    Text("先点左侧热搜词加载文章列表")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hotCommentPane: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("内容")
                            .font(.headline)
                        Spacer()
                    }
                    if let item = state.selectedItem {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: z(15), weight: .semibold))
                                .lineSpacing(4)
                                .lineLimit(3)
                            HStack(spacing: 8) {
                                Text(item.authorName)
                                Text("👍 \(item.voteCount)")
                                Text("💬 \(item.commentCount)")
                            }
                            .font(.system(size: z(12)))
                            .foregroundStyle(.secondary)

                            if !item.htmlContent.isEmpty {
                                HTMLWebView(html: item.htmlContent, textScale: state.userZoomScale)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView {
                                    Text(item.excerpt.isEmpty ? "暂无正文" : item.excerpt)
                                        .font(.system(size: z(13)))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        Text("先从中间选择一条文章")
                            .foregroundStyle(.secondary)
                            .font(.system(size: z(13)))
                    }
                }
                .padding(12)
                .frame(height: proxy.size.height * 0.56, alignment: .top)

                Rectangle()
                    .fill(sectionLineColor)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("评论")
                        .font(.title3.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HideEnclosingScrollView()
                                .frame(width: 0, height: 0)
                            if state.selectedItem == nil {
                                Text("先选择文章后查看评论")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: z(14)))
                            } else {
                                CommentsView()
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(12)
                .frame(height: proxy.size.height * 0.44, alignment: .top)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyHint: String {
        switch state.selectedTab {
        case .home:
            return "暂无推荐内容，点上方“刷新”重试"
        case .hotList:
            return "暂无热榜内容，点上方“刷新”重试"
        case .hotSearch:
            return "暂无热搜，点击上方“刷新”重试"
        }
    }

    private func contentPane(item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            (
                Text(item.title)
                    .font(.system(size: z(18), weight: .semibold))
                + Text("  \(item.authorName)  👍 \(item.voteCount)  💬 \(item.commentCount)")
                    .font(.system(size: z(13), weight: .medium))
                    .foregroundStyle(.secondary)
            )
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            if let url = item.webURL {
                Link("原文", destination: url)
                    .font(.system(size: z(13)))
            }

            if !item.htmlContent.isEmpty {
                HTMLWebView(html: item.htmlContent, textScale: state.userZoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(item.excerpt)
                        .font(.system(size: z(16)))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var commentsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HideEnclosingScrollView()
                    .frame(width: 0, height: 0)
                Text("评论")
                    .font(.headline)
                    .padding(.bottom, 4)
                CommentsView()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct CommentsView: View {
    @EnvironmentObject private var state: AppState
    private func z(_ size: CGFloat) -> CGFloat { size * state.userZoomScale }
    private var lineColor: Color {
        Color(nsColor: NSColor(srgbRed: 234/255, green: 234/255, blue: 234/255, alpha: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.comments.isEmpty {
                Text("暂无评论或正在加载")
                    .foregroundStyle(.secondary)
                    .font(.system(size: z(14)))
            }

            ForEach(state.comments) { comment in
                commentCard(comment)
            }
        }
    }

    @ViewBuilder
    private func commentCard(_ comment: CommentItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(comment.authorName)
                .font(.system(size: z(15), weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(comment.plainText.isEmpty ? "（空评论）" : comment.plainText)
                .font(.system(size: z(16)))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            childCommentsSection(for: comment)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
        )
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func childCommentsSection(for comment: CommentItem) -> some View {
        if comment.childCommentCount > 0 {
            if let children = state.childCommentsByParent[comment.id] {
                ForEach(children) { child in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(child.authorName)
                            .font(.system(size: z(14), weight: .semibold))
                        Text(child.plainText)
                            .font(.system(size: z(14)))
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .padding(.leading, 12)
                    .background(Color.gray.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(lineColor)
                            .frame(width: 1)
                            .padding(.vertical, 6)
                            .padding(.leading, 4)
                    }
                    .cornerRadius(6)
                }
            } else {
                Button("展开 \(comment.childCommentCount) 条子评论") {
                    Task { await state.loadChildComments(for: comment.id) }
                }
                .buttonStyle(.link)
            }
        }
    }
}
