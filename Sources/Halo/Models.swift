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
}
