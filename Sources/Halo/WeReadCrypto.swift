import Foundation
import CryptoKit
import CommonCrypto

enum WeReadCrypto {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - Hash functions

    static func md5(_ raw: String) -> String {
        let data = Data(raw.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ raw: String) -> String {
        let data = Data(raw.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Base64

    static func base64Decode(_ input: String) -> String {
        guard let data = Data(base64Encoded: input),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    static func base64Encode(_ input: String) -> String {
        return Data(input.utf8).base64EncodedString()
    }

    // MARK: - Decrypt

    static func decrypt(_ data: String) -> String {
        guard !data.isEmpty, data.count > 1 else { return "" }
        let sliced = String(data.dropFirst())

        let swapIndices = computeSwapIndices(sliced)
        let swapped = performSwaps(sliced, indices: swapIndices)
        return base64Decode(swapped)
    }

    private static func computeSwapIndices(_ result: String) -> [Int] {
        let len = result.count
        if len < 4 { return [] }
        if len < 11 { return [0, 2] }

        let prefixLen = min(4, Int(ceil(Double(len) / 10.0)))
        var str2 = ""
        let chars = Array(result)
        for i in stride(from: len - 1, to: len - 1 - prefixLen, by: -1) {
            let code = Int(chars[i].asciiValue ?? 0)
            let binary = String(code, radix: 2)
            if let parsed = Int(binary, radix: 4) {
                str2 += String(parsed)
            }
        }

        let mod = len - prefixLen - 2
        let digitCount = String(mod).count
        var indices: [Int] = []
        var pos = 0
        while indices.count < 10 && pos + digitCount < str2.count {
            let slice1 = String(str2[str2.index(str2.startIndex, offsetBy: pos)..<str2.index(str2.startIndex, offsetBy: pos + digitCount)])
            if let val1 = Int(slice1) {
                indices.append(val1 % mod)
            }
            let slice2 = String(str2[str2.index(str2.startIndex, offsetBy: pos + 1)..<str2.index(str2.startIndex, offsetBy: min(pos + 1 + digitCount, str2.count))])
            if let val2 = Int(slice2) {
                indices.append(val2 % mod)
            }
            pos += digitCount
        }
        return indices
    }

    private static func performSwaps(_ str: String, indices: [Int]) -> String {
        var chars = Array(str)
        var i = indices.count - 1
        while i >= 0 {
            for j in stride(from: 1, through: 0, by: -1) {
                let idx1 = indices[i] + j
                let idx2 = indices[i - 1] + j
                if idx1 < chars.count && idx2 < chars.count {
                    chars.swapAt(idx1, idx2)
                }
            }
            i -= 2
        }
        return String(chars)
    }

    // MARK: - Content decryptors

    static func dH(_ data: String) -> String {
        guard !data.isEmpty else { return "" }
        return decrypt(data)
    }

    static func dS(_ data: String) -> String {
        guard !data.isEmpty else { return "" }
        return decrypt(data)
    }

    static func dT(_ data: String) -> String {
        guard !data.isEmpty else { return "" }
        return decrypt(data)
    }

    // MARK: - Integrity check

    static func chk(_ data: String) -> String {
        guard !data.isEmpty, data.count > 32 else { return data }
        let header = String(data.prefix(32))
        let body = String(data.dropFirst(32))
        return header == md5(body).uppercased() ? body : ""
    }

    // MARK: - Payload signing

    static func sign(_ data: [String: Any]) -> String {
        let sorted = data.keys.sorted()
        var parts: [String] = []
        for key in sorted {
            if let value = data[key] {
                parts.append("\(key)=\(percentEncode("\(value)"))")
            }
        }
        let query = parts.joined(separator: "&")
        return _sign(query)
    }

    private static func _sign(_ data: String) -> String {
        var n1: Int32 = 0x15051505
        var n2: Int32 = 0x15051505
        let len = data.count
        let chars = Array(data)

        var i = len - 1
        while i > 0 {
            n1 = 0x7fffffff & (n1 ^ (Int32(chars[i].asciiValue ?? 0) << UInt32((len - i) % 30)))
            n2 = 0x7fffffff & (n2 ^ (Int32(chars[i - 1].asciiValue ?? 0) << UInt32(i % 30)))
            i -= 2
        }
        let result = Int(n1) + Int(n2)
        return String(format: "%x", result).lowercased()
    }

    private static func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    // MARK: - calcHash

    static func calcHash(_ data: Any) -> String {
        let str: String
        if let n = data as? Int {
            str = String(n)
        } else if let n = data as? Int64 {
            str = String(n)
        } else if let s = data as? String {
            str = s
        } else {
            return "\(data)"
        }

        let dataMd5 = md5(str)
        var result = String(dataMd5.prefix(3))

        let (typeCode, parts) = encodeForHash(str)
        result += typeCode
        result += "2" + String(dataMd5.suffix(2))

        for (idx, part) in parts.enumerated() {
            var hexLen = String(part.count, radix: 16)
            if hexLen.count == 1 { hexLen = "0" + hexLen }
            result += hexLen + part
            if idx < parts.count - 1 { result += "g" }
        }

        if result.count < 20 {
            result += String(dataMd5.prefix(20 - result.count))
        }

        return result + String(md5(result).prefix(3))
    }

    private static func encodeForHash(_ data: String) -> (String, [String]) {
        if isAllDigits(data) {
            var parts: [String] = []
            let chars = Array(data)
            var i = 0
            while i < chars.count {
                let end = min(i + 9, chars.count)
                let slice = String(chars[i..<end])
                if let val = Int(slice) {
                    parts.append(String(val, radix: 16))
                }
                i += 9
            }
            return ("3", parts)
        }

        var hex = ""
        for ch in data {
            if let code = ch.asciiValue {
                hex += String(Int(code), radix: 16)
            }
        }
        return ("4", [hex])
    }

    private static func isAllDigits(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.allSatisfy { $0.isNumber }
    }

    // MARK: - Time helpers

    static func currentTime() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    static func timestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - AppId

    static func getAppId(_ ua: String) -> String {
        let parts = ua.split(separator: " ")
        let count = min(parts.count, 12)
        var rnd1 = ""
        for i in 0..<count {
            rnd1 += String(parts[i].count % 10)
        }

        var num: Int32 = 0
        for ch in ua {
            num = (131 &* num &+ Int32(ch.asciiValue ?? 0)) & 0x7fffffff
        }
        var rnd2 = String(num)
        if rnd2.count > 16 {
            rnd2 = String(rnd2.prefix(16))
        }

        return "wb" + rnd1 + "h" + rnd2
    }
}
