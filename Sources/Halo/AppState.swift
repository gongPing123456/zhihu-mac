import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var username = "未登录"
    @Published var selectedTab: SidebarTab = .home
    @Published var homeReadMode: HomeReadMode = .withToken
    @Published var selectedHotSearchQuery: String?
    @Published var selectedHotListQuestionID: Int64?
    @Published var activeSearchQuery: String?
    @Published var searchText = ""
    @Published var isMoyuModeEnabled = false
    @Published var userZoomScale: CGFloat = 1.0
    @Published var feedItems: [FeedItem] = []
    @Published var hotListItems: [FeedItem] = []
    @Published var hotListContentItems: [FeedItem] = []
    @Published var searchResultItems: [FeedItem] = []
    @Published var hotSearchItems: [HotSearchItem] = []
    @Published var favoriteItems: [FeedItem] = []
    @Published var selectedItem: FeedItem?
    @Published var comments: [CommentItem] = []
    @Published var childCommentsByParent: [String: [CommentItem]] = [:]
    @Published var isLoading = false
    @Published var isLoadingMoreHome = false
    @Published var isLoadingMoreHotList = false
    @Published var errorMessage: String?
    @Published var contentLoadingItemID: String?

    // WeRead
    @Published var weReadBooks: [WeReadBook] = []
    @Published var weReadCatalog: [WeReadChapter] = []
    @Published var weReadCurrentBook: WeReadBook?
    @Published var weReadCurrentChapterIdx: Int = 0
    @Published var weReadChapterContent: WeReadChapterContent?
    @Published var weReadIsLoading = false
    @Published var weReadCookie: String?
    @Published var weReadViewMode: WeReadViewMode = .shelf
    @Published var weReadShowCookieSheet = false
    @Published var weReadShowCatalog = false
    @Published var weReadQuietMode = false
    private var weReadBookFormat: String?

    // API 搜索结果（回车触发）
    @Published var apiSearchResultItems: [FeedItem] = []
    @Published var apiSearchActiveQuery: String?

    private static let prefetchCount = 100

    private var homeNextURL: String?
    private var homeReachedEnd = false
    private var hotListContentNextURL: String?
    private var hotListContentReachedEnd = false
    private var fullContentPrefetchingIDs: Set<String> = []
    private var selectGeneration = 0
    private var lastSelectedItemIDByTab: [SidebarTab: String] = [:]
    private var preloadedCommentsCache: [String: [CommentItem]] = [:]

    private let api = ZhihuAPI()
    private let favoritesStore = FavoritesStore()
    private let homeRecommendationSuppressionStore = HomeRecommendationSuppressionStore()
    private let weReadAPI = WeReadAPI()

    init() {
        SessionStore.loadCookiesToSharedStorage()
        if let savedName = SessionStore.loadUsername(), !savedName.isEmpty {
            username = savedName
        }
        homeReadMode = SessionStore.loadHomeReadMode()
        favoriteItems = favoritesStore.load()
        weReadCookie = SessionStore.loadWeReadCookie()
    }

    var filteredFeedItems: [FeedItem] {
        guard !searchText.isEmpty else { return feedItems }
        return feedItems.filter { item in
            item.title.localizedCaseInsensitiveContains(searchText) ||
                item.excerpt.localizedCaseInsensitiveContains(searchText) ||
                item.authorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredHotListContentItems: [FeedItem] {
        guard !searchText.isEmpty else { return hotListContentItems }
        return hotListContentItems.filter { item in
            item.title.localizedCaseInsensitiveContains(searchText) ||
                item.excerpt.localizedCaseInsensitiveContains(searchText) ||
                item.authorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredHotSearchItems: [HotSearchItem] {
        hotSearchItems
    }

    var filteredFavoriteItems: [FeedItem] {
        guard !searchText.isEmpty else { return favoriteItems }
        return favoriteItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.authorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func items(for tab: SidebarTab) -> [FeedItem] {
        // API 搜索模式：优先返回 API 搜索结果
        if apiSearchActiveQuery != nil {
            return apiSearchResultItems
        }
        switch tab {
        case .home:
            return filteredFeedItems
        case .hotList:
            return filteredHotListContentItems
        case .hotSearch:
            return searchResultItems
        case .weread:
            return []
        }
    }

    func selectionProgress() -> (index: Int, total: Int)? {
        let candidates = items(for: selectedTab)
        guard !candidates.isEmpty,
              let current = selectedItem,
              let idx = candidates.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        return (idx + 1, candidates.count)
    }

    func initialLoad() async {
        await restoreLoginStatus()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshFeed() }
            group.addTask { await self.refreshHotList() }
            group.addTask { await self.refreshHotSearch() }
        }
        // 首屏加载完后，预加载当前 tab 首条内容，确保 ensureSelection 时内容已就绪
        await preloadFirstItemContent()
    }

    /// 为当前 tab 的第一条内容预加载全文，避免首屏出现 excerpt→HTML 的闪烁
    private func preloadFirstItemContent() async {
        let candidates = items(for: selectedTab)
        guard let first = candidates.first else { return }
        let includeLoginInfo = includeLoginInfo(for: first, in: selectedTab)
        await loadFullContent(for: first, isForSelectedItem: true, includeLoginInfo: includeLoginInfo)
        // 同步 selectedItem 指向最新版本（预加载已更新缓存）
        if let current = selectedItem, current.id == first.id,
           let fresh = items(for: selectedTab).first(where: { $0.id == first.id }) {
            selectedItem = fresh
            contentLoadingItemID = nil
        }
        // 同时预加载评论
        await preloadCommentsForItem(first)
    }

    func refreshCurrentTab() async {
        switch selectedTab {
        case .home:
            clearHomeStateForFullRefresh()
            await refreshFeed()
        case .hotList:
            clearHotListStateForFullRefresh()
            await refreshHotList()
        case .hotSearch:
            clearHotSearchStateForFullRefresh()
            await refreshHotSearch()
        case .weread:
            if weReadViewMode == .reader, let book = weReadCurrentBook {
                openWeReadBook(book)
            } else {
                await fetchWeReadShelf()
            }
        }
    }

    func refreshFeed() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.fetchRecommendedFeed(includeLoginInfo: shouldIncludeLoginInfoForHomeRequests)
            feedItems = filterHomeRecommendations(page.items, existingItems: [])
            homeNextURL = page.nextURL
            homeReachedEnd = page.isEnd
            if activeSearchQuery == nil {
                searchResultItems = []
            }
            errorMessage = nil
            ensureSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHotSearch() async {
        do {
            hotSearchItems = deduplicateHotSearchItems(try await api.fetchHotSearch())
            if let selected = selectedHotSearchQuery,
               !hotSearchItems.contains(where: { $0.query == selected }) {
                selectedHotSearchQuery = nil
            }
            errorMessage = nil
            await ensureHotSearchDefaultLoaded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHotList() async {
        do {
            hotListItems = deduplicateFeedItems(try await api.fetchHotList())
            if let qid = selectedHotListQuestionID,
               !hotListItems.contains(where: { $0.contentId == qid }) {
                selectedHotListQuestionID = nil
            }
            errorMessage = nil
            await ensureHotListDefaultLoaded()
        } catch {
            if selectedTab == .hotList {
                errorMessage = "热榜加载失败：\(error.localizedDescription)"
            }
        }
    }

    func select(_ item: FeedItem?) {
        // 用 candidates 中最新版本（预加载可能已更新 htmlContent）
        var latestItem = item
        if let item {
            let candidates = items(for: selectedTab)
            if let fresh = candidates.first(where: { $0.id == item.id }) {
                latestItem = fresh
            }
        }
        childCommentsByParent = [:]
        guard let item = latestItem else {
            selectedItem = nil; comments = []; contentLoadingItemID = nil; return
        }
        let includeLoginInfo = includeLoginInfo(for: item, in: selectedTab)
        let includeLoginInfoForComments = includeLoginInfoForComments(in: selectedTab)

        // 立即切换（预加载命中则直接显示全文，否则显示摘要）
        selectedItem = item
        lastSelectedItemIDByTab[selectedTab] = item.id
        contentLoadingItemID = nil

        // 评论：优先用缓存
        if let cachedComments = preloadedCommentsCache[item.id] {
            comments = cachedComments
        } else {
            comments = []
        }

        // 当前项内容+评论：独立 Task
        Task {
            if item.htmlContent.isEmpty && !fullContentPrefetchingIDs.contains(item.id) {
                await loadFullContent(for: item, isForSelectedItem: true, includeLoginInfo: includeLoginInfo)
            }
            if preloadedCommentsCache[item.id] == nil {
                await loadComments(for: item, includeLoginInfo: includeLoginInfoForComments)
            }
        }
        // 预取后续内容：fire-and-forget，立即批量启动
        prefetchWindowAroundSelection()
    }

    func loadComments(for item: FeedItem, includeLoginInfo: Bool = true) async {
        do {
            comments = try await api.fetchRootComments(for: item, includeLoginInfo: includeLoginInfo)
        } catch {
            comments = []
            // 评论加载失败静默处理，不显示顶部错误条（评论是辅助内容）
        }
    }

    func loadChildComments(for parentCommentID: String) async {
        if childCommentsByParent[parentCommentID] != nil { return }
        do {
            let children = try await api.fetchChildComments(
                commentID: parentCommentID,
                includeLoginInfo: includeLoginInfoForComments(in: selectedTab)
            )
            childCommentsByParent[parentCommentID] = children
        } catch {
            // 子评论加载失败静默处理
        }
    }

    func preloadCommentsForItem(_ item: FeedItem) async {
        guard preloadedCommentsCache[item.id] == nil else { return }
        let includeLoginInfoForComments = includeLoginInfoForComments(in: selectedTab)
        do {
            let comments = try await api.fetchRootComments(for: item, includeLoginInfo: includeLoginInfoForComments)
            preloadedCommentsCache[item.id] = comments
        } catch {
            // 静默失败，不影响主流程
        }
    }

    func toggleFavorite(for item: FeedItem) {
        if favoriteItems.contains(where: { $0.id == item.id }) {
            favoriteItems.removeAll { $0.id == item.id }
        } else {
            favoriteItems.insert(item, at: 0)
        }
        favoritesStore.save(favoriteItems)
    }

    func isFavorite(_ item: FeedItem) -> Bool {
        favoriteItems.contains { $0.id == item.id }
    }

    private func loadFullContent(for item: FeedItem, isForSelectedItem: Bool, includeLoginInfo: Bool = true) async {
        if item.htmlContent.isEmpty == false { return }
        if fullContentPrefetchingIDs.contains(item.id) { return }
        fullContentPrefetchingIDs.insert(item.id)
        defer { fullContentPrefetchingIDs.remove(item.id) }

        do {
            guard let full = try await api.fetchFullContent(for: item, includeLoginInfo: includeLoginInfo), !full.isEmpty else { return }
            let updated = FeedItem(
                id: item.id,
                contentType: item.contentType,
                contentId: item.contentId,
                questionId: item.questionId,
                title: item.title,
                excerpt: item.excerpt,
                htmlContent: full,
                authorName: item.authorName,
                authorAvatar: item.authorAvatar,
                voteCount: item.voteCount,
                commentCount: item.commentCount
            )
            replaceItemInCaches(with: updated)
            if isForSelectedItem, let current = selectedItem, current.id == item.id {
                selectedItem = updated
            }
        } catch {
            // 忽略补拉失败，不影响主流程
        }
    }

    private func replaceItemInCaches(with item: FeedItem) {
        if let idx = feedItems.firstIndex(where: { $0.id == item.id }) {
            feedItems[idx] = item
        }
        if let idx = hotListContentItems.firstIndex(where: { $0.id == item.id }) {
            hotListContentItems[idx] = item
        }
        if let idx = searchResultItems.firstIndex(where: { $0.id == item.id }) {
            searchResultItems[idx] = item
        }
        if let idx = favoriteItems.firstIndex(where: { $0.id == item.id }) {
            favoriteItems[idx] = item
            favoritesStore.save(favoriteItems)
        }
    }

    private func prefetchWindowAroundSelection() {
        let candidates = items(for: selectedTab)
        guard !candidates.isEmpty,
              let current = selectedItem,
              let idx = candidates.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        let upper = min(candidates.count - 1, idx + Self.prefetchCount)
        let includeLoginInfo = includeLoginInfo(for: current, in: selectedTab)

        // 全部 fire-and-forget，立即返回不阻塞
        for offset in 1 ... Self.prefetchCount {
            let forwardIndex = idx + offset
            if forwardIndex <= upper {
                let item = candidates[forwardIndex]
                Task { await self.loadFullContent(for: item, isForSelectedItem: false, includeLoginInfo: includeLoginInfo) }
                Task { await self.preloadCommentsForItem(item) }
            }
        }
        if idx - 1 >= 0 {
            Task { await self.loadFullContent(for: candidates[idx - 1], isForSelectedItem: false, includeLoginInfo: includeLoginInfo) }
            Task { await self.preloadCommentsForItem(candidates[idx - 1]) }
        }
    }

    func ensureSelection() {
        let candidates = items(for: selectedTab)
        guard !candidates.isEmpty else {
            selectedItem = nil
            comments = []
            childCommentsByParent = [:]
            return
        }

        if let current = selectedItem, candidates.contains(where: { $0.id == current.id }) {
            lastSelectedItemIDByTab[selectedTab] = current.id
            return
        }

        if let rememberedID = lastSelectedItemIDByTab[selectedTab],
           let remembered = candidates.first(where: { $0.id == rememberedID }) {
            select(remembered)
            return
        }
        select(candidates.first)
    }

    func moveSelection(step: Int) {
        let candidates = items(for: selectedTab)
        guard !candidates.isEmpty else { return }
        guard let current = selectedItem, let idx = candidates.firstIndex(where: { $0.id == current.id }) else {
            select(candidates.first)
            return
        }

        if step > 0 &&
            selectedTab == .home &&
            activeSearchQuery == nil &&
            idx == candidates.count - 1 &&
            !homeReachedEnd {
            Task {
                await loadMoreHomeAndAdvance(fromIndex: idx)
            }
            return
        }

        if step > 0 &&
            selectedTab == .hotList &&
            idx == candidates.count - 1 &&
            !hotListContentReachedEnd {
            Task {
                await loadMoreHotListAndAdvance(fromIndex: idx)
            }
            return
        }

        let nextIdx = min(max(0, idx + step), candidates.count - 1)
        if nextIdx != idx {
            select(candidates[nextIdx])
        }
    }

    private func loadMoreHomeAndAdvance(fromIndex oldLastIndex: Int) async {
        await loadMoreHome()
        let candidates = items(for: .home)
        guard candidates.count > oldLastIndex + 1 else { return }
        let target = candidates[oldLastIndex + 1]
        // 先预取目标项及后续几篇，避免翻页时闪摘要
        let includeLoginInfo = includeLoginInfo(for: target, in: .home)
        await loadFullContent(for: target, isForSelectedItem: false, includeLoginInfo: includeLoginInfo)
        // 预取后续 2 篇
        for offset in 1...2 {
            let idx = oldLastIndex + 1 + offset
            if idx < candidates.count {
                Task { await self.loadFullContent(for: candidates[idx], isForSelectedItem: false, includeLoginInfo: includeLoginInfo) }
            }
        }
        select(target)
    }

    private func loadMoreHotListAndAdvance(fromIndex oldLastIndex: Int) async {
        await loadMoreHotListContents()
        let candidates = items(for: .hotList)
        guard candidates.count > oldLastIndex + 1 else { return }
        let target = candidates[oldLastIndex + 1]
        let includeLoginInfo = includeLoginInfo(for: target, in: .hotList)
        await loadFullContent(for: target, isForSelectedItem: false, includeLoginInfo: includeLoginInfo)
        for offset in 1...2 {
            let idx = oldLastIndex + 1 + offset
            if idx < candidates.count {
                Task { await self.loadFullContent(for: candidates[idx], isForSelectedItem: false, includeLoginInfo: includeLoginInfo) }
            }
        }
        select(target)
    }

    func loadMoreHome() async {
        guard !isLoadingMoreHome else { return }
        guard !homeReachedEnd else { return }
        guard let next = homeNextURL, !next.isEmpty else {
            homeReachedEnd = true
            return
        }

        isLoadingMoreHome = true
        defer { isLoadingMoreHome = false }
        do {
            let page = try await api.fetchRecommendedFeed(
                nextURL: next,
                includeLoginInfo: shouldIncludeLoginInfoForHomeRequests
            )
            homeNextURL = page.nextURL
            homeReachedEnd = page.isEnd

            let filteredIncoming = filterHomeRecommendations(page.items, existingItems: feedItems)
            feedItems.append(contentsOf: filteredIncoming)
            errorMessage = nil
        } catch {
            errorMessage = "加载更多失败：\(error.localizedDescription)"
        }
    }

    func searchFromHotQuery(_ query: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let results = deduplicateFeedItems(try await api.fetchSearchResults(query: query))
            selectedHotSearchQuery = query
            activeSearchQuery = query
            searchText = query
            searchResultItems = results
            errorMessage = results.isEmpty ? "未找到相关内容" : nil
            ensureSelection()
        } catch {
            errorMessage = "搜索失败：\(error.localizedDescription)"
        }
    }

    func clearActiveSearchIfNeeded() {
        if activeSearchQuery != nil && searchText.isEmpty {
            activeSearchQuery = nil
            selectedHotSearchQuery = nil
            searchResultItems = []
            ensureSelection()
        }
    }

    /// 清空本地搜索文字（不清除已缓存的文章内容）
    func clearLocalSearch() {
        guard !searchText.isEmpty || apiSearchActiveQuery != nil else { return }
        searchText = ""
        apiSearchActiveQuery = nil
        apiSearchResultItems = []
        ensureSelectionAfterSearchChange()
    }

    /// 搜索文字变化回调（由 UI 调用，解决 toolbar TextField 不触发 didSet 的问题）
    func searchTextChanged() {
        // 如果正在 API 搜索模式中，修改搜索词则退出 API 搜索，回到本地过滤
        if apiSearchActiveQuery != nil {
            apiSearchActiveQuery = nil
            apiSearchResultItems = []
        }
        ensureSelectionAfterSearchChange()
    }

    /// 回车提交搜索：调用知乎 API 搜索
    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            apiSearchActiveQuery = nil
            apiSearchResultItems = []
            ensureSelectionAfterSearchChange()
            return
        }
        apiSearchActiveQuery = query
        isLoading = true
        Task {
            do {
                let results = deduplicateFeedItems(try await api.fetchSearchResults(query: query))
                apiSearchResultItems = results
                errorMessage = results.isEmpty ? "未找到「\(query)」相关内容" : nil
                ensureSelection()
            } catch {
                apiSearchResultItems = []
                errorMessage = "搜索失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// 搜索文字变化后，确保选中项仍在过滤结果中
    private func ensureSelectionAfterSearchChange() {
        let candidates = items(for: selectedTab)
        // 当前选中项仍在过滤结果中，无需切换
        if let current = selectedItem, candidates.contains(where: { $0.id == current.id }) {
            return
        }
        // 选中过滤结果的第一项
        if let first = candidates.first {
            select(first)
        } else {
            selectedItem = nil
            comments = []
            childCommentsByParent = [:]
        }
    }

    func ensureHotSearchDefaultLoaded() async {
        guard selectedTab == .hotSearch else { return }
        guard !hotSearchItems.isEmpty else { return }
        let defaultQuery = selectedHotSearchQuery ?? hotSearchItems[0].query
        let shouldReload = selectedHotSearchQuery == nil || searchResultItems.isEmpty
        selectedHotSearchQuery = defaultQuery
        if shouldReload {
            await searchFromHotQuery(defaultQuery)
        }
    }

    func ensureHotListDefaultLoaded() async {
        guard selectedTab == .hotList else { return }
        guard !hotListItems.isEmpty else { return }
        let defaultID = selectedHotListQuestionID ?? hotListItems[0].contentId
        let shouldReload = selectedHotListQuestionID == nil || hotListContentItems.isEmpty
        selectedHotListQuestionID = defaultID
        if shouldReload {
            await loadHotListContents(questionID: defaultID)
        }
    }

    func loadHotListContents(questionID: Int64) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.fetchQuestionFeeds(questionID: questionID)
            let items = deduplicateFeedItems(page.items)
            selectedHotListQuestionID = questionID
            hotListContentItems = items
            hotListContentNextURL = page.nextURL
            hotListContentReachedEnd = page.isEnd
            errorMessage = items.isEmpty ? "该热点暂无可展示文章（可能需要登录）" : nil
            ensureSelection()
        } catch {
            hotListContentItems = []
            hotListContentNextURL = nil
            hotListContentReachedEnd = false
            errorMessage = "热榜文章加载失败：\(error.localizedDescription)"
        }
    }

    func loadMoreHotListContents() async {
        guard !isLoadingMoreHotList else { return }
        guard !hotListContentReachedEnd else { return }
        guard let questionID = selectedHotListQuestionID else { return }
        guard let next = hotListContentNextURL, !next.isEmpty else {
            hotListContentReachedEnd = true
            return
        }

        isLoadingMoreHotList = true
        defer { isLoadingMoreHotList = false }
        do {
            let page = try await api.fetchQuestionFeeds(questionID: questionID, nextURL: next)
            hotListContentNextURL = page.nextURL
            hotListContentReachedEnd = page.isEnd
            hotListContentItems = deduplicateFeedItems(hotListContentItems + page.items)
            errorMessage = nil
        } catch {
            errorMessage = "热榜文章加载更多失败：\(error.localizedDescription)"
        }
    }

    func restoreLoginStatus() async {
        do {
            let name = try await api.verifyLogin()
            isLoggedIn = true
            username = name
            SessionStore.saveUsername(name)
        } catch {
            isLoggedIn = false
            username = "未登录"
            SessionStore.saveUsername("")
        }
    }

    func completeLogin(with cookies: [HTTPCookie]) async -> String? {
        SessionStore.saveCookies(cookies)
        do {
            let name = try await api.verifyLogin()
            isLoggedIn = true
            username = name
            SessionStore.saveUsername(name)
            return nil
        } catch {
            isLoggedIn = false
            username = "未登录"
            return "登录验证失败，请确认知乎登录成功后重试"
        }
    }

    func logout() {
        SessionStore.clearSession()
        isLoggedIn = false
        username = "未登录"
    }

    func decreaseZoom() {
        userZoomScale = max(0.75, userZoomScale - 0.05)
    }

    func increaseZoom() {
        userZoomScale = min(1.30, userZoomScale + 0.05)
    }

    func resetZoom() {
        userZoomScale = 1.0
    }

    func setHomeReadMode(_ mode: HomeReadMode) {
        guard homeReadMode != mode else { return }
        homeReadMode = mode
        SessionStore.saveHomeReadMode(mode)
        if selectedTab == .home {
            Task { await refreshCurrentTab() }
        }
    }

    // MARK: - WeRead

    var isWeReadLoggedIn: Bool {
        guard let cookie = weReadCookie, !cookie.isEmpty else { return false }
        return cookie.contains("wr_skey") && cookie.contains("wr_vid")
    }

    func saveWeReadCookie(_ cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        weReadCookie = trimmed
        SessionStore.saveWeReadCookie(trimmed)
        weReadShowCookieSheet = false
        Task { await fetchWeReadShelf() }
    }

    func logoutWeRead() {
        weReadCookie = nil
        weReadBooks = []
        weReadCatalog = []
        weReadCurrentBook = nil
        weReadChapterContent = nil
        weReadViewMode = .shelf
        SessionStore.clearWeReadCookie()
    }

    func fetchWeReadShelf() async {
        // Load cached shelf first
        if weReadBooks.isEmpty, let cached = WeReadChapterCache.loadShelf() {
            weReadBooks = cached
        }
        guard let cookie = weReadCookie else { return }
        weReadIsLoading = true
        defer { weReadIsLoading = false }
        do {
            let books = try await weReadAPI.fetchShelf(cookie: cookie)
            weReadBooks = books
            WeReadChapterCache.saveShelf(books)
            errorMessage = nil
        } catch {
            errorMessage = "书架加载失败：\(error.localizedDescription)"
        }
    }

    func openWeReadBook(_ book: WeReadBook) {
        weReadCurrentBook = book
        weReadViewMode = .reader
        weReadIsLoading = true
        weReadCatalog = []
        weReadCurrentChapterIdx = 0
        weReadChapterContent = nil
        weReadBookFormat = nil

        // Try cached catalog first
        if let cached = WeReadChapterCache.loadCatalog(bookId: book.id) {
            weReadCatalog = cached.catalog
            weReadBookFormat = cached.format
            // Load first cached chapter immediately
            if !cached.catalog.isEmpty {
                Task { await loadWeReadChapter(idx: 0, silent: true) }
            }
            weReadIsLoading = false
            // Still pre-fetch uncached chapters if cookie available
            if let cookie = weReadCookie {
                preFetchAllChapters(bookId: book.id, format: cached.format, cookie: cookie)
            }
            return
        }

        guard let cookie = weReadCookie else { return }

        Task {
            do {
                let format: String
                do {
                    format = try await weReadAPI.fetchBookInfo(bookId: book.id, cookie: cookie)
                } catch {
                    print("[WeRead] fetchBookInfo failed: \(error)")
                    throw error
                }
                weReadBookFormat = format

                let catalog: [WeReadChapter]
                do {
                    catalog = try await weReadAPI.fetchChapterInfos(bookId: book.id, cookie: cookie)
                } catch {
                    print("[WeRead] fetchChapterInfos failed: \(error)")
                    throw error
                }
                weReadCatalog = catalog

                // Save catalog to cache
                WeReadChapterCache.saveCatalog(bookId: book.id, catalog: catalog, format: format)

                let progressChapterUid: Int?
                do {
                    progressChapterUid = try await weReadAPI.fetchProgress(bookId: book.id, cookie: cookie)
                } catch {
                    print("[WeRead] fetchProgress failed: \(error)")
                    progressChapterUid = nil
                }

                if let uid = progressChapterUid, let idx = catalog.firstIndex(where: { $0.chapterUid == uid }) {
                    weReadCurrentChapterIdx = idx
                    await loadWeReadChapter(idx: idx, silent: true)
                } else if !catalog.isEmpty {
                    await loadWeReadChapter(idx: 0, silent: true)
                }
                weReadIsLoading = false

                // Pre-fetch all remaining chapters in background
                preFetchAllChapters(bookId: book.id, format: format, cookie: cookie)
            } catch {
                errorMessage = "书籍加载失败：\(error.localizedDescription)"
                weReadIsLoading = false
            }
        }
    }

    private func preFetchAllChapters(bookId: String, format: String, cookie: String) {
        Task.detached { [weak self] in
            guard let self else { return }
            let catalog = await self.weReadCatalog
            let concurrency = 3
            var index = 0

            await withTaskGroup(of: Void.self) { group in
                while index < catalog.count {
                    // Fill up to `concurrency` concurrent tasks
                    for _ in 0..<concurrency {
                        guard index < catalog.count else { break }
                        let chapter = catalog[index]
                        index += 1

                        // Skip if already cached
                        if WeReadChapterCache.load(bookId: bookId, chapterUid: chapter.chapterUid) != nil {
                            continue
                        }

                        group.addTask {
                            do {
                                let content = try await self.weReadAPI.fetchChapterContent(
                                    bookId: bookId, chapterUid: chapter.chapterUid, format: format, cookie: cookie
                                )
                                WeReadChapterCache.save(bookId: bookId, chapterUid: chapter.chapterUid, content: content)
                                print("[WeRead] Cached chapter: \(chapter.title)")
                            } catch {
                                print("[WeRead] Pre-fetch failed for \(chapter.title): \(error)")
                            }
                            // Small delay to avoid rate limiting
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                    }
                    // Wait for current batch before starting next
                    for await _ in group {}
                }
            }
            print("[WeRead] Pre-fetch complete for book \(bookId)")
        }
    }

    func loadWeReadChapter(idx: Int, silent: Bool = false) async {
        guard let book = weReadCurrentBook else { return }
        guard idx >= 0 && idx < weReadCatalog.count else { return }

        weReadIsLoading = true
        weReadCurrentChapterIdx = idx

        let chapter = weReadCatalog[idx]

        // Try cache first
        if let cached = WeReadChapterCache.load(bookId: book.id, chapterUid: chapter.chapterUid) {
            weReadChapterContent = cached
            weReadIsLoading = false
            return
        }

        guard let cookie = weReadCookie else { return }
        do {
            let format = weReadBookFormat ?? "epub"
            let content = try await weReadAPI.fetchChapterContent(bookId: book.id, chapterUid: chapter.chapterUid, format: format, cookie: cookie)
            weReadChapterContent = content
            weReadIsLoading = false

            // Cache content locally
            WeReadChapterCache.save(bookId: book.id, chapterUid: chapter.chapterUid, content: content)

            // Report reading progress (fire-and-forget)
            if !silent {
                Task {
                    do {
                        let readerToken = try await weReadAPI.reportReadInit(bookId: book.id, chapterUid: chapter.chapterUid, format: content.format, cookie: cookie)
                        if let readerToken {
                            try await weReadAPI.reportRead(bookId: book.id, chapterUid: chapter.chapterUid, format: content.format, readerToken: readerToken, cookie: cookie)
                        }
                    } catch { }
                }
            }
        } catch {
            // Try cache on failure
            let chapter = weReadCatalog[idx]
            if let cached = WeReadChapterCache.load(bookId: book.id, chapterUid: chapter.chapterUid) {
                weReadChapterContent = cached
                weReadIsLoading = false
            } else {
                errorMessage = "章节加载失败：\(error.localizedDescription)"
                weReadIsLoading = false
            }
        }
    }

    func weReadMoveChapter(step: Int) {
        let newIdx = weReadCurrentChapterIdx + step
        guard newIdx >= 0 && newIdx < weReadCatalog.count else { return }
        Task { await loadWeReadChapter(idx: newIdx) }
    }

    var shouldIncludeLoginInfoForHomeRequests: Bool {
        homeReadMode == .withToken
    }

    private func clearHomeStateForFullRefresh() {
        feedItems = []
        selectedItem = nil
        comments = []
        childCommentsByParent = [:]
        errorMessage = nil
        homeNextURL = nil
        homeReachedEnd = false
        lastSelectedItemIDByTab[.home] = nil
        if activeSearchQuery == nil {
            searchResultItems = []
        }
    }

    private func clearHotListStateForFullRefresh() {
        hotListItems = []
        hotListContentItems = []
        selectedHotListQuestionID = nil
        hotListContentNextURL = nil
        hotListContentReachedEnd = false
        selectedItem = nil
        comments = []
        childCommentsByParent = [:]
        errorMessage = nil
        lastSelectedItemIDByTab[.hotList] = nil
    }

    private func clearHotSearchStateForFullRefresh() {
        hotSearchItems = []
        searchResultItems = []
        selectedHotSearchQuery = nil
        activeSearchQuery = nil
        selectedItem = nil
        comments = []
        childCommentsByParent = [:]
        errorMessage = nil
        lastSelectedItemIDByTab[.hotSearch] = nil
    }

    private func deduplicateFeedItems(_ items: [FeedItem]) -> [FeedItem] {
        var result: [FeedItem] = []
        var indexByID: [String: Int] = [:]

        for item in items {
            if let existingIndex = indexByID[item.id] {
                let existing = result[existingIndex]
                result[existingIndex] = preferredFeedItem(existing: existing, incoming: item)
            } else {
                indexByID[item.id] = result.count
                result.append(item)
            }
        }

        return result
    }

    private func filterHomeRecommendations(_ incomingItems: [FeedItem], existingItems: [FeedItem]) -> [FeedItem] {
        let idDeduplicated = deduplicateFeedItems(incomingItems)
        var result: [FeedItem] = []
        var existingIDs = Set(existingItems.map(\.id))
        var seenBatchSignatures = Set(existingItems.compactMap(homeRecommendationSignature))

        for item in idDeduplicated {
            if existingIDs.contains(item.id) {
                continue
            }

            if let signature = homeRecommendationSignature(item) {
                if seenBatchSignatures.contains(signature) {
                    continue
                }
                if homeRecommendationSuppressionStore.isSuppressed(signature: signature) {
                    continue
                }
                seenBatchSignatures.insert(signature)
                homeRecommendationSuppressionStore.remember(signature: signature)
            }

            if let existingIndex = result.firstIndex(where: { $0.id == item.id }) {
                let existing = result[existingIndex]
                result[existingIndex] = preferredFeedItem(existing: existing, incoming: item)
                continue
            }

            result.append(item)
            existingIDs.insert(item.id)
        }

        return result
    }

    private func preferredFeedItem(existing: FeedItem, incoming: FeedItem) -> FeedItem {
        if existing.htmlContent.isEmpty && !incoming.htmlContent.isEmpty {
            return incoming
        }
        if existing.excerpt.isEmpty && !incoming.excerpt.isEmpty {
            return incoming
        }
        return existing
    }

    private func deduplicateHotSearchItems(_ items: [HotSearchItem]) -> [HotSearchItem] {
        var seenQueries: Set<String> = []
        return items.filter { item in
            seenQueries.insert(item.query).inserted
        }
    }

    private func normalizedHomeDedupTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\[[^\\]]+\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func homeRecommendationSignature(_ item: FeedItem) -> String? {
        let normalizedAuthor = item.authorName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = normalizedHomeDedupTitle(item.title)
        guard !normalizedAuthor.isEmpty, !normalizedTitle.isEmpty else { return nil }
        return "\(normalizedAuthor)|\(normalizedTitle)"
    }

    private func includeLoginInfo(for item: FeedItem, in tab: SidebarTab) -> Bool {
        if tab == .home, feedItems.contains(where: { $0.id == item.id }) {
            return shouldIncludeLoginInfoForHomeRequests
        }
        return true
    }

    private func includeLoginInfoForComments(in tab: SidebarTab) -> Bool {
        if tab == .home {
            return isLoggedIn
        }
        return true
    }
}

private struct FavoritesStore {
    private let key = "moyu.favorites"

    func load() -> [FeedItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FeedItem].self, from: data)) ?? []
    }

    func save(_ items: [FeedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct HomeRecommendationSuppressionStore {
    private let key = "moyu.home.recommendation.suppression"
    private let calendar = Calendar(identifier: .gregorian)
    private let retentionDays = 30

    func isSuppressed(signature: String, now: Date = Date()) -> Bool {
        let map = prunedStorage(now: now)
        guard let timestamp = map[signature] else { return false }
        return now.timeIntervalSince1970 - timestamp < TimeInterval(retentionDays * 24 * 60 * 60)
    }

    func remember(signature: String, now: Date = Date()) {
        var map = prunedStorage(now: now)
        map[signature] = now.timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: key)
    }

    private func prunedStorage(now: Date) -> [String: TimeInterval] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now)?.timeIntervalSince1970 ?? 0
        let pruned = raw.filter { $0.value >= cutoff }
        if pruned.count != raw.count {
            UserDefaults.standard.set(pruned, forKey: key)
        }
        return pruned
    }
}
