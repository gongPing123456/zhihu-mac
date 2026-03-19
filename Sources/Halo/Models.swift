import Foundation

enum ZhihuContentType: String, Codable {
    case answer
    case article
    case pin
    case question
    case unknown
}

struct FeedItem: Identifiable, Codable, Hashable {
    let id: String
    let contentType: ZhihuContentType
    let contentId: Int64
    let questionId: Int64?
    let title: String
    let excerpt: String
    let htmlContent: String
    let authorName: String
    let authorAvatar: String?
    let voteCount: Int
    let commentCount: Int

    var webURL: URL? {
        switch contentType {
        case .answer:
            if let qid = questionId {
                return URL(string: "https://www.zhihu.com/question/\(qid)/answer/\(contentId)")
            }
            return URL(string: "https://www.zhihu.com/answer/\(contentId)")
        case .article:
            return URL(string: "https://zhuanlan.zhihu.com/p/\(contentId)")
        case .pin:
            return URL(string: "https://www.zhihu.com/pin/\(contentId)")
        case .question:
            return URL(string: "https://www.zhihu.com/question/\(contentId)")
        case .unknown:
            return nil
        }
    }
}

struct CommentItem: Identifiable, Codable {
    let id: String
    let authorName: String
    let contentHTML: String
    let plainText: String
    let childCommentCount: Int

    var imageURLs: [URL] {
        contentHTML.extractImageURLs()
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case home = "首页"
    case hotSearch = "热搜"
    case hotList = "热榜"

    var id: String { rawValue }
}

struct HotSearchItem: Identifiable, Codable {
    let id: String
    let query: String
    let hotDisplay: String
}

extension String {
    func strippingHTML() -> String {
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let withoutEntities = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return withoutEntities
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractImageURLs() -> [URL] {
        let patterns = [
            #"data-original\s*=\s*"([^"]+)""#,
            #"data-actualsrc\s*=\s*"([^"]+)""#,
            #"data-src\s*=\s*"([^"]+)""#,
            #"src\s*=\s*"([^"]+)""#,
            #"href\s*=\s*"([^"]+)""#
        ]
        var result: [URL] = []
        var seen: Set<String> = []
        let range = NSRange(location: 0, length: utf16.count)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: self, options: [], range: range) {
                guard match.numberOfRanges >= 2,
                      let valueRange = Range(match.range(at: 1), in: self) else { continue }
                var raw = String(self[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty || raw.hasPrefix("data:") { continue }
                if raw.hasPrefix("//") { raw = "https:" + raw }
                raw = raw.replacingOccurrences(of: "&amp;", with: "&")
                guard let url = URL(string: raw) else { continue }
                guard looksLikeImageURL(url) else { continue }
                let key = url.absoluteString
                if seen.contains(key) { continue }
                seen.insert(key)
                result.append(url)
            }
        }
        return result
    }

    private func looksLikeImageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") ||
            path.hasSuffix(".png") || path.hasSuffix(".gif") ||
            path.hasSuffix(".webp") || path.hasSuffix(".heic") ||
            path.hasSuffix(".bmp") || path.hasSuffix(".svg") {
            return true
        }

        if let host = url.host?.lowercased(), host.contains("zhimg.com") || host.contains("zhihu.com") {
            return true
        }

        let query = url.query?.lowercased() ?? ""
        if query.contains("image") || query.contains("img") || query.contains("pic") {
            return true
        }

        return false
    }
}
