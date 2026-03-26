import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case badStatus(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL 无效"
        case .invalidResponse:
            return "响应数据无效"
        case let .badStatus(code):
            return "请求失败，状态码：\(code)"
        case let .serverMessage(msg):
            return msg
        }
    }
}

actor ZhihuAPI {
    struct RecommendPage {
        let items: [FeedItem]
        let nextURL: String?
        let isEnd: Bool
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let anonymousSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func fetchRecommendedFeed(nextURL: String? = nil, includeLoginInfo: Bool = true) async throws -> RecommendPage {
        let urlString = nextURL ?? "https://api.zhihu.com/topstory/recommend"
        let request = try makeRequest(urlString: urlString, includeLoginInfo: includeLoginInfo)
        let (data, response) = try await data(for: request, includeLoginInfo: includeLoginInfo)
        try validate(response)
        return try parseRecommendFeed(data: data)
    }

    func fetchHotSearch() async throws -> [HotSearchItem] {
        let request = try makeRequest(urlString: "https://www.zhihu.com/api/v4/search/hot_search")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try parseHotSearch(data: data)
    }

    func fetchRootComments(for item: FeedItem, includeLoginInfo: Bool = true) async throws -> [CommentItem] {
        guard let path = commentPath(for: item) else { return [] }

        let urlString = "https://www.zhihu.com/api/v4/comment_v5/\(path)/root_comment?limit=20"
        let request = try makeRequest(urlString: urlString, includeLoginInfo: includeLoginInfo)
        let (data, response) = try await data(for: request, includeLoginInfo: includeLoginInfo)
        try validate(response)
        let payload = try decoder.decode(CommentResponse.self, from: data)
        return payload.data.map {
            CommentItem(
                id: $0.id.value,
                authorName: $0.author?.name ?? "匿名",
                contentHTML: $0.content ?? "",
                plainText: ($0.content ?? "").strippingHTML(),
                childCommentCount: $0.childCommentCount ?? 0
            )
        }
    }

    func fetchFullContent(for item: FeedItem, includeLoginInfo: Bool = true) async throws -> String? {
        let urlString: String
        switch item.contentType {
        case .answer:
            urlString = "https://www.zhihu.com/api/v4/answers/\(item.contentId)?include=content"
        case .article:
            urlString = "https://www.zhihu.com/api/v4/articles/\(item.contentId)?include=content"
        case .pin:
            urlString = "https://www.zhihu.com/api/v4/pins/\(item.contentId)"
        case .question, .unknown:
            return nil
        }

        let request = try makeRequest(urlString: urlString, includeLoginInfo: includeLoginInfo)
        let (data, response) = try await data(for: request, includeLoginInfo: includeLoginInfo)
        try validate(response)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let content = root["content"] as? String, !content.isEmpty {
            return content
        }
        if let content = root["content_html"] as? String, !content.isEmpty {
            return content
        }
        return nil
    }

    func fetchChildComments(commentID: String, includeLoginInfo: Bool = true) async throws -> [CommentItem] {
        let urlString = "https://www.zhihu.com/api/v4/comment_v5/comment/\(commentID)/child_comment?limit=20"
        let request = try makeRequest(urlString: urlString, includeLoginInfo: includeLoginInfo)
        let (data, response) = try await data(for: request, includeLoginInfo: includeLoginInfo)
        try validate(response)
        let payload = try decoder.decode(CommentResponse.self, from: data)
        return payload.data.map {
            CommentItem(
                id: $0.id.value,
                authorName: $0.author?.name ?? "匿名",
                contentHTML: $0.content ?? "",
                plainText: ($0.content ?? "").strippingHTML(),
                childCommentCount: $0.childCommentCount ?? 0
            )
        }
    }

    func fetchSearchResults(query: String) async throws -> [FeedItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        let url = "https://www.zhihu.com/api/v4/search_v3?gk_version=gz-gaokao&t=general&q=\(encoded)&correction=1&search_source=Normal&limit=20&include=data[*].highlight,object,type"
        let request = try makeRequest(urlString: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try parseSearchResults(data: data)
    }

    func fetchHotList() async throws -> [FeedItem] {
        let request = try makeRequest(urlString: "https://api.zhihu.com/topstory/hot-lists/total?limit=50&mobile=true")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try parseHotList(data: data)
    }

    func fetchQuestionFeeds(questionID: Int64) async throws -> [FeedItem] {
        let request = try makeRequest(urlString: "https://www.zhihu.com/api/v4/questions/\(questionID)/feeds?limit=20")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try parseQuestionFeeds(data: data)
    }

    func verifyLogin() async throws -> String {
        let request = try makeRequest(urlString: "https://www.zhihu.com/api/v4/me")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = root["name"] as? String,
            !name.isEmpty
        else {
            throw APIError.invalidResponse
        }
        return name
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }

    private func commentPath(for item: FeedItem) -> String? {
        switch item.contentType {
        case .answer:
            return "answers/\(item.contentId)"
        case .article:
            return "articles/\(item.contentId)"
        case .pin:
            return "pins/\(item.contentId)"
        case .question:
            return "questions/\(item.contentId)"
        case .unknown:
            return nil
        }
    }

    private func makeRequest(urlString: String, includeLoginInfo: Bool = true) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = includeLoginInfo
        if includeLoginInfo, let cookie = SessionStore.cookieHeader(), !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        } else {
            request.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func data(for request: URLRequest, includeLoginInfo: Bool) async throws -> (Data, URLResponse) {
        if includeLoginInfo {
            return try await URLSession.shared.data(for: request)
        }
        return try await anonymousSession.data(for: request)
    }

    private func parseRecommendFeed(data: Data) throws -> RecommendPage {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataList = root["data"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }

        let items: [FeedItem] = dataList.compactMap { (card: [String: Any]) -> FeedItem? in
            guard let target = card["target"] as? [String: Any] else { return nil }
            let brief = BriefType.parse(from: card["brief"] as? String)

            let contentType = brief?.type ?? ZhihuContentType(rawValue: (target["type"] as? String) ?? "") ?? .unknown
            let contentId = brief?.id ?? target.int64("id") ?? 0
            guard contentId > 0 else { return nil }

            let question = target["question"] as? [String: Any]
            let questionId = question?.int64("id")
            let title = (question?["title"] as? String) ?? (target["title"] as? String) ?? "无标题"
            let excerpt = ((target["excerpt"] as? String) ?? "").strippingHTML()
            let htmlContent = (target["content"] as? String) ?? ""

            let author = target["author"] as? [String: Any]
            let authorName = (author?["name"] as? String) ?? "匿名"
            let authorAvatar = (author?["avatar_url"] as? String) ?? (author?["avatarUrl"] as? String)
            let voteCount = target.int("voteup_count") ?? target.int("voteupCount") ?? target.int("vote_count") ?? target.int("voteCount") ?? 0
            let commentCount = target.int("comment_count") ?? target.int("commentCount") ?? 0

            return FeedItem(
                id: "\(contentType.rawValue)-\(contentId)",
                contentType: contentType,
                contentId: contentId,
                questionId: questionId,
                title: title,
                excerpt: excerpt,
                htmlContent: htmlContent,
                authorName: authorName,
                authorAvatar: authorAvatar,
                voteCount: voteCount,
                commentCount: commentCount
            )
        }

        let paging = root["paging"] as? [String: Any]
        let nextURL = paging?["next"] as? String
        let isEnd: Bool = {
            if let value = paging?["is_end"] as? Bool { return value }
            if let value = paging?["isEnd"] as? Bool { return value }
            return nextURL == nil
        }()

        return RecommendPage(items: items, nextURL: nextURL, isEnd: isEnd)
    }

    private func parseHotSearch(data: Data) throws -> [HotSearchItem] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let queries = root["hot_search_queries"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }

        return queries.enumerated().compactMap { index, item in
            let query = ((item["real_query"] as? String) ?? (item["query"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            let rawID = (item["query_id"] as? String)
                ?? (item["query_id"] as? NSNumber)?.stringValue
                ?? "q"
            let id = "\(rawID)-\(index)-\(query)"
            let hotDisplay = (item["hot_show"] as? String) ?? ""
            return HotSearchItem(id: id, query: query, hotDisplay: hotDisplay)
        }
    }

    private func parseSearchResults(data: Data) throws -> [FeedItem] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataList = root["data"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }

        return dataList.compactMap { card in
            guard let object = card["object"] as? [String: Any] else { return nil }
            let type = (object["type"] as? String) ?? "unknown"
            let contentType = ZhihuContentType(rawValue: type) ?? .unknown
            let contentId = object.int64("id") ?? 0
            guard contentId > 0 else { return nil }

            let question = object["question"] as? [String: Any]
            let questionId = question?.int64("id")
            let title = (question?["title"] as? String) ?? (object["title"] as? String) ?? "无标题"
            let excerpt = ((object["excerpt"] as? String) ?? "").strippingHTML()
            let htmlContent = (object["content"] as? String) ?? ""
            let author = object["author"] as? [String: Any]
            let authorName = (author?["name"] as? String) ?? "匿名"
            let authorAvatar = (author?["avatar_url"] as? String) ?? (author?["avatarUrl"] as? String)
            let voteCount = object.int("voteup_count") ?? object.int("vote_count") ?? 0
            let commentCount = object.int("comment_count") ?? 0

            return FeedItem(
                id: "\(contentType.rawValue)-\(contentId)",
                contentType: contentType,
                contentId: contentId,
                questionId: questionId,
                title: title,
                excerpt: excerpt,
                htmlContent: htmlContent,
                authorName: authorName,
                authorAvatar: authorAvatar,
                voteCount: voteCount,
                commentCount: commentCount
            )
        }
    }

    private func parseHotList(data: Data) throws -> [FeedItem] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataList = root["data"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }

        return dataList.compactMap { card in
            guard let target = card["target"] as? [String: Any] else { return nil }
            let questionId = target.int64("id") ?? 0
            guard questionId > 0 else { return nil }
            let title = (target["title"] as? String) ?? "无标题"
            let excerpt = ((target["excerpt"] as? String) ?? (target["detail"] as? String) ?? "").strippingHTML()
            let answerCount = target.int("answer_count") ?? target.int("answerCount") ?? 0
            let followerCount = target.int("follower_count") ?? target.int("followerCount") ?? 0

            return FeedItem(
                id: "question-\(questionId)",
                contentType: .question,
                contentId: questionId,
                questionId: nil,
                title: title,
                excerpt: excerpt,
                htmlContent: "",
                authorName: "热榜",
                authorAvatar: nil,
                voteCount: followerCount,
                commentCount: answerCount
            )
        }
    }

    private func parseQuestionFeeds(data: Data) throws -> [FeedItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "热榜文章加载失败"
            throw APIError.serverMessage(message)
        }
        guard let dataList = root["data"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return dataList.compactMap { card in
            guard let target = card["target"] as? [String: Any] else { return nil }
            let type = (target["type"] as? String) ?? "unknown"
            let contentType = ZhihuContentType(rawValue: type) ?? .unknown
            guard contentType == .answer || contentType == .article else { return nil }

            let contentId = target.int64("id") ?? 0
            guard contentId > 0 else { return nil }
            let question = target["question"] as? [String: Any]
            let questionId = question?.int64("id")
            let title = (question?["title"] as? String) ?? (target["title"] as? String) ?? "无标题"
            let excerpt = ((target["excerpt"] as? String) ?? "").strippingHTML()
            let htmlContent = (target["content"] as? String) ?? ""
            let author = target["author"] as? [String: Any]
            let authorName = (author?["name"] as? String) ?? "匿名"
            let authorAvatar = (author?["avatar_url"] as? String) ?? (author?["avatarUrl"] as? String)
            let voteCount = target.int("voteup_count") ?? target.int("vote_count") ?? 0
            let commentCount = target.int("comment_count") ?? 0

            return FeedItem(
                id: "\(contentType.rawValue)-\(contentId)",
                contentType: contentType,
                contentId: contentId,
                questionId: questionId,
                title: title,
                excerpt: excerpt,
                htmlContent: htmlContent,
                authorName: authorName,
                authorAvatar: authorAvatar,
                voteCount: voteCount,
                commentCount: commentCount
            )
        }
    }
}

private struct APIAuthor: Decodable {
    let name: String?
    let avatarURL: String?
}

private struct CommentResponse: Decodable {
    let data: [CommentDTO]
}

private struct CommentDTO: Decodable {
    let id: StringOrInt
    let content: String?
    let childCommentCount: Int?
    let author: APIAuthor?
}

private struct StringOrInt: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int64.self) {
            value = "\(int)"
        } else if let int = try? container.decode(Int.self) {
            value = "\(int)"
        } else {
            value = UUID().uuidString
        }
    }
}

private struct BriefType: Decodable {
    let type: ZhihuContentType
    let id: Int64

    static func parse(from raw: String?) -> BriefType? {
        guard let raw else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(BriefType.self, from: data)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let value = self[key] as? Int64 { return value }
        if let value = self[key] as? Int { return Int64(value) }
        if let value = self[key] as? NSNumber { return value.int64Value }
        if let value = self[key] as? String { return Int64(value) }
        return nil
    }
}
