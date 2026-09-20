import Foundation
import CommonCrypto

/// 知乎 Web 端 `x-zse-96` 签名算法（v2，zse-v4 魔改 AES/SM4 变种）。
/// 参考 zhihu-plus-plus（zly2006）`ZseSigner` + `ZhihuFetchSignature` 的实现移植。
enum ZhihuSignature {
    private static let zk: [UInt32] = [
        1170614578, 1024848638, 1413669199, 3951632832, 3528873006, 2921909214, 4151847688, 3997739139,
        1933479194, 3323781115, 3888513386, 460404854, 3747539722, 2403641034, 2615871395, 2119585428,
        2265697227, 2035090028, 2773447226, 4289380121, 4217216195, 2200601443, 3051914490, 1579901135,
        1321810770, 456816404, 2903323407, 4065664991, 330002838, 3506006750, 363569021, 2347096187,
    ]

    private static let zb: [UInt8] = [
        20, 223, 245, 7, 248, 2, 194, 209, 87, 6, 227, 253, 240, 128, 222, 91, 237, 9, 125, 157, 230,
        93, 252, 205, 90, 79, 144, 199, 159, 197, 186, 167, 39, 37, 156, 198, 38, 42, 43, 168, 217,
        153, 15, 103, 80, 189, 71, 191, 97, 84, 247, 95, 36, 69, 14, 35, 12, 171, 28, 114, 178, 148,
        86, 182, 32, 83, 158, 109, 22, 255, 94, 238, 151, 85, 77, 124, 254, 18, 4, 26, 123, 176, 232,
        193, 131, 172, 143, 142, 150, 30, 10, 146, 162, 62, 224, 218, 196, 229, 1, 192, 213, 27, 110,
        56, 231, 180, 138, 107, 242, 187, 54, 120, 19, 44, 117, 228, 215, 203, 53, 239, 251, 127, 81,
        11, 133, 96, 204, 132, 41, 115, 73, 55, 249, 147, 102, 48, 122, 145, 106, 118, 74, 190, 29, 16,
        174, 5, 177, 129, 63, 113, 99, 31, 161, 76, 246, 34, 211, 13, 60, 68, 207, 160, 65, 111, 82,
        165, 67, 169, 225, 57, 112, 244, 155, 51, 236, 200, 233, 58, 61, 47, 100, 137, 185, 64, 17, 70,
        234, 163, 219, 108, 170, 166, 59, 149, 52, 105, 24, 212, 78, 173, 45, 0, 116, 226, 119, 136,
        206, 135, 175, 195, 25, 92, 121, 208, 126, 139, 3, 75, 141, 21, 130, 98, 241, 40, 154, 66, 184,
        49, 181, 46, 243, 88, 101, 183, 8, 23, 72, 188, 104, 179, 210, 134, 250, 201, 164, 89, 216,
        202, 220, 50, 221, 152, 140, 33, 235, 214,
    ]

    private static let alphabet = Array("6fpLRqJO8M/c3jnYxFkUVC4ZIG12SiH=5v0mXDazWBTsuw7QetbKdoPyAl+hN9rgE")
    private static let key16: [UInt8] = Array("059053f7d15e01d7".utf8)

    // MARK: - 对外入口

    /// 生成 x-zse-96 头（含 "2.0_" 前缀）。
    static func zse96Header(url: String, dc0: String, body: String? = nil) -> String {
        let pathname = "/" + url.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true).dropFirst(2).joined(separator: "/")
        var parts = ["101_3_3.0", pathname, dc0]
        if let body, !body.isEmpty {
            parts.append(body)
        }
        let signSource = parts.joined(separator: "+")
        let md5 = md5Hex(signSource)
        return "2.0_" + encryptZseV4(md5)
    }

    // MARK: - MD5

    private static func md5Hex(_ s: String) -> String {
        let data = Array(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func rotateLeft(_ v: UInt32, by n: UInt32) -> UInt32 {
        (v << n) | (v >> (32 - n))
    }

    // MARK: - ZSE v4 魔改 AES

    private static func gTransform(_ tt: UInt32) -> UInt32 {
        let te0 = UInt8((tt >> 24) & 0xff)
        let te1 = UInt8((tt >> 16) & 0xff)
        let te2 = UInt8((tt >> 8) & 0xff)
        let te3 = UInt8(tt & 0xff)
        let ti = (UInt32(zb[Int(te0)]) << 24)
            | (UInt32(zb[Int(te1)]) << 16)
            | (UInt32(zb[Int(te2)]) << 8)
            | UInt32(zb[Int(te3)])
        return ti ^ rotateLeft(ti, by: 2) ^ rotateLeft(ti, by: 10) ^ rotateLeft(ti, by: 18) ^ rotateLeft(ti, by: 24)
    }

    private static func rBlock(_ input16: [UInt8]) -> [UInt8] {
        var tr = [UInt32](repeating: 0, count: 36)
        for i in 0 ..< 4 {
            tr[i] = (UInt32(input16[i * 4]) << 24)
                | (UInt32(input16[i * 4 + 1]) << 16)
                | (UInt32(input16[i * 4 + 2]) << 8)
                | UInt32(input16[i * 4 + 3])
        }
        for i in 0 ..< 32 {
            let ta = gTransform(tr[i + 1] ^ tr[i + 2] ^ tr[i + 3] ^ zk[i])
            tr[i + 4] = tr[i] ^ ta
        }
        var out = [UInt8](repeating: 0, count: 16)
        for (idx, v) in [tr[35], tr[34], tr[33], tr[32]].enumerated() {
            out[idx * 4] = UInt8((v >> 24) & 0xff)
            out[idx * 4 + 1] = UInt8((v >> 16) & 0xff)
            out[idx * 4 + 2] = UInt8((v >> 8) & 0xff)
            out[idx * 4 + 3] = UInt8(v & 0xff)
        }
        return out
    }

    private static func xBlocks(_ data: [UInt8], _ iv0: [UInt8]) -> [UInt8] {
        var iv = iv0
        var out = [UInt8]()
        var off = 0
        while off < data.count {
            var mixed = [UInt8](repeating: 0, count: 16)
            for i in 0 ..< 16 {
                mixed[i] = data[off + i] ^ iv[i]
            }
            iv = rBlock(mixed)
            out.append(contentsOf: iv)
            off += 16
        }
        return out
    }

    private static func customEncode(_ bytesIn: [UInt8]) -> String {
        var bytes = bytesIn
        while bytes.count % 3 != 0 {
            bytes.append(0)
        }
        var out = ""
        var i = 0
        var p = bytes.count - 1
        while p >= 0 {
            var v: UInt32 = 0
            let b0 = UInt32(bytes[p])
            let m0 = (UInt32(58) >> UInt32(8 * (i % 4))) & 0xff
            i += 1
            v |= (b0 ^ m0) & 0xff

            let b1 = UInt32(bytes[p - 1])
            let m1 = (UInt32(58) >> UInt32(8 * (i % 4))) & 0xff
            i += 1
            v |= ((b1 ^ m1) & 0xff) << 8

            let b2 = UInt32(bytes[p - 2])
            let m2 = (UInt32(58) >> UInt32(8 * (i % 4))) & 0xff
            i += 1
            v |= ((b2 ^ m2) & 0xff) << 16

            out.append(alphabet[Int(v & 63)])
            out.append(alphabet[Int((v >> 6) & 63)])
            out.append(alphabet[Int((v >> 12) & 63)])
            out.append(alphabet[Int((v >> 18) & 63)])
            p -= 3
        }
        return out
    }

    private static func encryptZseV4(_ input: String) -> String {
        var plain: [UInt8] = [210, 0] // seed = 0xD2
        plain.append(contentsOf: Array(input.utf8))
        let pad = 16 - (plain.count % 16)
        for _ in 0 ..< pad {
            plain.append(UInt8(pad))
        }

        var first = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 16 {
            first[i] = plain[i] ^ key16[i] ^ 42
        }

        let c0 = rBlock(first)
        var cipher = c0
        if plain.count > 16 {
            cipher.append(contentsOf: xBlocks(Array(plain[16...]), c0))
        }
        return customEncode(cipher)
    }
}
