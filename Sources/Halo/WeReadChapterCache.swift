import Foundation

enum WeReadChapterCache {
    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WeReadChapters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(bookId: String, chapterUid: Int, content: WeReadChapterContent) {
        let file = cacheDir.appendingPathComponent("\(bookId)_\(chapterUid).json")
        let dict: [String: Any] = [
            "html": content.html,
            "style": content.style,
            "format": content.format,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: file)
    }

    static func load(bookId: String, chapterUid: Int) -> WeReadChapterContent? {
        let file = cacheDir.appendingPathComponent("\(bookId)_\(chapterUid).json")
        guard let data = try? Data(contentsOf: file),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = dict["html"] as? String,
              let format = dict["format"] as? String else {
            return nil
        }
        let style = dict["style"] as? String ?? ""
        return WeReadChapterContent(html: html, style: style, format: format)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
