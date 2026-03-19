import Foundation

enum SessionStore {
    private static let cookiesKey = "moyu.zhihu.cookies"
    private static let usernameKey = "moyu.zhihu.username"

    static func saveCookies(_ cookies: [HTTPCookie]) {
        let zhihuCookies = cookies.filter { cookie in
            (cookie.domain.contains("zhihu.com") || cookie.domain.contains(".zhihu.com")) && !cookie.name.isEmpty
        }
        let serialized: [[String: Any]] = zhihuCookies.map { cookie in
            var item: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure
            ]
            if let expires = cookie.expiresDate?.timeIntervalSince1970 {
                item["expires"] = expires
            }
            return item
        }
        UserDefaults.standard.set(serialized, forKey: cookiesKey)
        loadCookiesToSharedStorage()
    }

    static func loadCookiesToSharedStorage() {
        guard let array = UserDefaults.standard.array(forKey: cookiesKey) as? [[String: Any]] else { return }
        let storage = HTTPCookieStorage.shared
        for item in array {
            guard
                let name = item["name"] as? String,
                let value = item["value"] as? String,
                let domain = item["domain"] as? String,
                let path = item["path"] as? String
            else { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path,
            ]
            if let expires = item["expires"] as? TimeInterval {
                props[.expires] = Date(timeIntervalSince1970: expires)
            }
            if let secure = item["secure"] as? Bool {
                props[.secure] = secure
            }
            if let cookie = HTTPCookie(properties: props) {
                storage.setCookie(cookie)
            }
        }
    }

    static func cookieHeader() -> String? {
        let cookies = HTTPCookieStorage.shared.cookies?.filter {
            $0.domain.contains("zhihu.com") || $0.domain.contains(".zhihu.com")
        } ?? []
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: cookiesKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    static func saveUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    static func loadUsername() -> String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }
}
