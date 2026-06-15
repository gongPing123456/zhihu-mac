import Foundation

enum WeReadChapterCache {
    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WeReadChapters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Chapter Content

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

    static func isChapterCached(bookId: String, chapterUid: Int) -> Bool {
        let file = cacheDir.appendingPathComponent("\(bookId)_\(chapterUid).json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    // MARK: - Catalog

    static func saveCatalog(bookId: String, catalog: [WeReadChapter], format: String) {
        let file = cacheDir.appendingPathComponent("\(bookId)_catalog.json")
        let items: [[String: Any]] = catalog.map { ch in
            ["id": ch.id, "chapterUid": ch.chapterUid, "title": ch.title, "level": ch.level]
        }
        let dict: [String: Any] = ["catalog": items, "format": format]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: file)
    }

    static func loadCatalog(bookId: String) -> (catalog: [WeReadChapter], format: String)? {
        let file = cacheDir.appendingPathComponent("\(bookId)_catalog.json")
        guard let data = try? Data(contentsOf: file),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = dict["catalog"] as? [[String: Any]],
              let format = dict["format"] as? String else {
            return nil
        }
        let catalog = items.compactMap { d -> WeReadChapter? in
            guard let id = d["id"] as? Int,
                  let uid = d["chapterUid"] as? Int,
                  let title = d["title"] as? String else { return nil }
            let level = d["level"] as? Int ?? 0
            return WeReadChapter(id: id, chapterUid: uid, title: title, level: level)
        }
        return (catalog, format)
    }

    // MARK: - Shelf

    static func saveShelf(_ books: [WeReadBook]) {
        let file = cacheDir.appendingPathComponent("shelf.json")
        let items: [[String: Any]] = books.map { b in
            var dict: [String: Any] = ["id": b.id, "title": b.title, "cover": b.cover]
            if let t = b.readUpdateTime { dict["readUpdateTime"] = t }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items) else { return }
        try? data.write(to: file)
    }

    static func loadShelf() -> [WeReadBook]? {
        let file = cacheDir.appendingPathComponent("shelf.json")
        guard let data = try? Data(contentsOf: file),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let books = items.compactMap { d -> WeReadBook? in
            guard let id = d["id"] as? String, let title = d["title"] as? String else { return nil }
            let cover = d["cover"] as? String ?? ""
            let updateTime = d["readUpdateTime"] as? Int
            return WeReadBook(id: id, title: title, cover: cover, readUpdateTime: updateTime)
        }
        return books.isEmpty ? nil : books
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
