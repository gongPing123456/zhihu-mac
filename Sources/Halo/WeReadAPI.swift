import Foundation

enum WeReadAPIError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingFailed
    case decryptFailed
    case authExpired
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .httpError(let code): return "HTTP 错误: \(code)"
        case .decodingFailed: return "数据解析失败"
        case .decryptFailed: return "内容解密失败"
        case .authExpired: return "微信读书登录已过期，请重新设置 Cookie"
        case .unsupportedFormat(let fmt): return "不支持的格式: \(fmt)"
        }
    }
}

actor WeReadAPI {
    private let baseURL = "https://weread.qq.com"
    private let session: URLSession
    private let appId: String

    init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
        self.appId = WeReadCrypto.getAppId(WeReadCrypto.userAgent)
    }

    // MARK: - Shelf

    func fetchShelf(cookie: String) async throws -> [WeReadBook] {
        let url = URL(string: "\(baseURL)/web/shelf/sync")!
        let data = try await get(url: url, query: [:], cookie: cookie)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let booksData = json["books"] as? [[String: Any]] else {
            throw WeReadAPIError.decodingFailed
        }
        return booksData.compactMap { dict in
            guard let bookId = dict["bookId"] as? String else { return nil }
            // bookId 可能是 Int 或 String
            let id = "\(bookId)"
            let title = dict["title"] as? String ?? ""
            let cover = dict["cover"] as? String ?? ""
            let updateTime = dict["readUpdateTime"] as? Int
            return WeReadBook(id: id, title: title, cover: cover, readUpdateTime: updateTime)
        }
    }

    // MARK: - Book Info

    func fetchBookInfo(bookId: String, cookie: String) async throws -> String {
        let url = URL(string: "\(baseURL)/web/book/info")!
        let data = try await get(url: url, query: ["bookId": bookId], cookie: cookie)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? String else {
            throw WeReadAPIError.decodingFailed
        }
        return format
    }

    // MARK: - Chapter Infos (catalog)

    func fetchChapterInfos(bookId: String, cookie: String) async throws -> [WeReadChapter] {
        let url = URL(string: "\(baseURL)/web/book/chapterInfos")!
        let body: [String: Any] = ["bookIds": [bookId]]
        let data = try await postJSON(url: url, body: body, cookie: cookie)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first else {
            throw WeReadAPIError.decodingFailed
        }

        let chapters: [[String: Any]]
        if let updated = first["updated"] as? [[String: Any]] {
            chapters = updated
        } else if let chaps = first["chapters"] as? [[String: Any]] {
            chapters = chaps
        } else {
            chapters = []
        }

        return chapters.compactMap { dict in
            guard let uid = dict["chapterUid"] as? Int else { return nil }
            let title = dict["title"] as? String ?? ""
            let level = dict["level"] as? Int ?? 0
            return WeReadChapter(id: uid, chapterUid: uid, title: title, level: level)
        }
    }

    // MARK: - Progress

    func fetchProgress(bookId: String, cookie: String) async throws -> Int? {
        let url = URL(string: "\(baseURL)/web/book/getProgress")!
        let data = try await get(url: url, query: ["bookId": bookId], cookie: cookie)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let book = json["book"] as? [String: Any],
              let chapterUid = book["chapterUid"] as? Int else {
            return nil
        }
        return chapterUid
    }

    // MARK: - Chapter Content

    func fetchChapterContent(bookId: String, chapterUid: Int, cookie: String) async throws -> WeReadChapterContent {
        let format = try await fetchBookInfo(bookId: bookId, cookie: cookie)

        if format == "epub" || format == "pdf" {
            let results = try await (
                fetchChapterPart(bookId: bookId, chapterUid: chapterUid, part: 0, st: 0, cookie: cookie),
                fetchChapterPart(bookId: bookId, chapterUid: chapterUid, part: 1, st: 0, cookie: cookie),
                fetchChapterPart(bookId: bookId, chapterUid: chapterUid, part: 2, st: 1, cookie: cookie),
                fetchChapterPart(bookId: bookId, chapterUid: chapterUid, part: 3, st: 0, cookie: cookie)
            )
            guard !results.0.isEmpty, !results.1.isEmpty, !results.3.isEmpty else {
                throw WeReadAPIError.decryptFailed
            }
            let html = WeReadCrypto.dH(results.0 + results.1 + results.3)
            let style = WeReadCrypto.dS(results.2)
            return WeReadChapterContent(html: html, style: style, format: format)
        } else if format == "txt" {
            let results = try await (
                fetchChapterPartTxt(bookId: bookId, chapterUid: chapterUid, part: 0, st: 0, cookie: cookie),
                fetchChapterPartTxt(bookId: bookId, chapterUid: chapterUid, part: 1, st: 1, cookie: cookie)
            )
            guard !results.0.isEmpty, !results.1.isEmpty else {
                throw WeReadAPIError.decryptFailed
            }
            let html = WeReadCrypto.dT(results.0 + results.1)
            return WeReadChapterContent(html: html, style: "", format: format)
        } else {
            throw WeReadAPIError.unsupportedFormat(format)
        }
    }

    private func fetchChapterPart(bookId: String, chapterUid: Int, part: Int, st: Int, cookie: String) async throws -> String {
        let r = Int(pow(Double(10000 * Double.random(in: 0...1)), 2))
        let payload: [String: Any] = [
            "b": WeReadCrypto.calcHash(bookId),
            "c": WeReadCrypto.calcHash(chapterUid),
            "r": r,
            "st": st,
            "ct": WeReadCrypto.currentTime(),
            "ps": "a2b325707a19e580g0186a2",
            "pc": "430321207a19e581g013ab0",
        ]
        let signed = signPayload(payload)
        let url = URL(string: "\(baseURL)/web/book/chapter/e_\(part)")!
        let data = try await postJSON(url: url, body: signed, cookie: cookie)
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return WeReadCrypto.chk(text)
    }

    private func fetchChapterPartTxt(bookId: String, chapterUid: Int, part: Int, st: Int, cookie: String) async throws -> String {
        let r = Int(pow(Double(10000 * Double.random(in: 0...1)), 2))
        let payload: [String: Any] = [
            "b": WeReadCrypto.calcHash(bookId),
            "c": WeReadCrypto.calcHash(chapterUid),
            "r": r,
            "st": st,
            "ct": WeReadCrypto.currentTime(),
            "ps": "a2b325707a19e580g0186a2",
            "pc": "430321207a19e581g013ab0",
        ]
        let signed = signPayload(payload)
        let url = URL(string: "\(baseURL)/web/book/chapter/t_\(part)")!
        let data = try await postJSON(url: url, body: signed, cookie: cookie)
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return WeReadCrypto.chk(text)
    }

    // MARK: - Report Read

    func reportReadInit(bookId: String, chapterUid: Int, format: String, cookie: String) async throws -> String? {
        var payload: [String: Any] = [
            "appId": appId,
            "b": WeReadCrypto.calcHash(bookId),
            "c": WeReadCrypto.calcHash(chapterUid),
            "ci": chapterUid,
            "co": 0,
            "ct": WeReadCrypto.currentTime(),
            "dy": 0,
            "fm": format,
            "pc": WeReadCrypto.calcHash(0),
            "pr": 0,
            "ps": WeReadCrypto.calcHash(0),
            "sm": "",
        ]
        payload["s"] = WeReadCrypto.sign(payload)
        let url = URL(string: "\(baseURL)/web/book/read")!
        let data = try await postJSON(url: url, body: payload, cookie: cookie)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["readerToken"] as? String
    }

    func reportRead(bookId: String, chapterUid: Int, format: String, readerToken: String, cookie: String) async throws {
        let ts = WeReadCrypto.timestamp()
        let rnd = Int.random(in: 0..<1000)
        var payload: [String: Any] = [
            "appId": appId,
            "b": WeReadCrypto.calcHash(bookId),
            "c": WeReadCrypto.calcHash(chapterUid),
            "ci": chapterUid,
            "co": 0,
            "ct": WeReadCrypto.currentTime(),
            "dy": 0,
            "fm": format,
            "pc": WeReadCrypto.calcHash(0),
            "pr": 0,
            "ps": WeReadCrypto.calcHash(0),
            "sm": "",
            "rt": 60,
            "ts": ts,
            "rn": rnd,
            "sg": WeReadCrypto.sha256("\(ts)\(rnd)\(readerToken)"),
        ]
        payload["s"] = WeReadCrypto.sign(payload)
        let url = URL(string: "\(baseURL)/web/book/read")!
        _ = try await postJSON(url: url, body: payload, cookie: cookie)
    }

    // MARK: - Helpers

    private func signPayload(_ payload: [String: Any]) -> [String: Any] {
        var result = payload
        result["s"] = WeReadCrypto.sign(payload)
        return result
    }

    private func get(url: URL, query: [String: String], cookie: String) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(WeReadCrypto.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return data
    }

    private func postJSON(url: URL, body: [String: Any], cookie: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(WeReadCrypto.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return data
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WeReadAPIError.authExpired
        }
        guard (200...299).contains(http.statusCode) else {
            throw WeReadAPIError.httpError(http.statusCode)
        }
    }
}
