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
    @Published var errorMessage: String?

    private var homeNextURL: String?
    private var homeReachedEnd = false
    private var fullContentPrefetchingIDs: Set<String> = []
    private var lastSelectedItemIDByTab: [SidebarTab: String] = [:]

    private let api = ZhihuAPI()
    private let favoritesStore = FavoritesStore()

    init() {
        SessionStore.loadCookiesToSharedStorage()
        if let savedName = SessionStore.loadUsername(), !savedName.isEmpty {
            username = savedName
        }
        homeReadMode = SessionStore.loadHomeReadMode()
        favoriteItems = favoritesStore.load()
    }

    var filteredFeedItems: [FeedItem] {
        if activeSearchQuery != nil {
            return searchResultItems
        }
        guard !searchText.isEmpty else { return feedItems }
        return feedItems.filter { item in
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
        switch tab {
        case .home:
            return filteredFeedItems
        case .hotList:
            return hotListContentItems
        case .hotSearch:
            return searchResultItems
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
        }
    }

    func refreshFeed() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.fetchRecommendedFeed(includeLoginInfo: shouldIncludeLoginInfoForHomeRequests)
            feedItems = deduplicateFeedItems(page.items)
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
        selectedItem = item
        if let item {
            lastSelectedItemIDByTab[selectedTab] = item.id
        }
        comments = []
        childCommentsByParent = [:]
        guard let item else { return }
        let includeLoginInfo = includeLoginInfo(for: item, in: selectedTab)
        Task {
            await loadComments(for: item, includeLoginInfo: includeLoginInfo)
            await loadFullContent(for: item, isForSelectedItem: true, includeLoginInfo: includeLoginInfo)
        }
        Task { await prefetchWindowAroundSelection() }
    }

    func loadComments(for item: FeedItem, includeLoginInfo: Bool = true) async {
        do {
            comments = try await api.fetchRootComments(for: item, includeLoginInfo: includeLoginInfo)
            errorMessage = nil
        } catch {
            comments = []
            errorMessage = "评论加载失败：\(error.localizedDescription)"
        }
    }

    func loadChildComments(for parentCommentID: String) async {
        if childCommentsByParent[parentCommentID] != nil { return }
        do {
            let children = try await api.fetchChildComments(
                commentID: parentCommentID,
                includeLoginInfo: selectedTab == .home ? shouldIncludeLoginInfoForHomeRequests : true
            )
            childCommentsByParent[parentCommentID] = children
        } catch {
            errorMessage = "子评论加载失败：\(error.localizedDescription)"
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

    private func prefetchWindowAroundSelection() async {
        let candidates = items(for: selectedTab)
        guard !candidates.isEmpty,
              let current = selectedItem,
              let idx = candidates.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        let lower = max(0, idx - 2)
        let upper = min(candidates.count - 1, idx + 7)
        let includeLoginInfo = includeLoginInfo(for: current, in: selectedTab)
        for i in lower ... upper {
            let item = candidates[i]
            let isSelected = (item.id == current.id)
            await loadFullContent(for: item, isForSelectedItem: isSelected, includeLoginInfo: includeLoginInfo)
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

        let nextIdx = min(max(0, idx + step), candidates.count - 1)
        if nextIdx != idx {
            select(candidates[nextIdx])
        }
    }

    private func loadMoreHomeAndAdvance(fromIndex oldLastIndex: Int) async {
        await loadMoreHome()
        let candidates = items(for: .home)
        if candidates.count > oldLastIndex + 1 {
            select(candidates[oldLastIndex + 1])
        }
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

            feedItems = deduplicateFeedItems(feedItems + page.items)
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
            let items = deduplicateFeedItems(try await api.fetchQuestionFeeds(questionID: questionID))
            selectedHotListQuestionID = questionID
            hotListContentItems = items
            errorMessage = items.isEmpty ? "该热点暂无可展示文章（可能需要登录）" : nil
            ensureSelection()
        } catch {
            hotListContentItems = []
            errorMessage = "热榜文章加载失败：\(error.localizedDescription)"
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

    private func includeLoginInfo(for item: FeedItem, in tab: SidebarTab) -> Bool {
        if tab == .home, feedItems.contains(where: { $0.id == item.id }) {
            return shouldIncludeLoginInfoForHomeRequests
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
