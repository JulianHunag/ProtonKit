import Foundation

public enum Bcrypt {
    private static let bcryptBase64Chars = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
    private static let ciphertext = Array("OrpheanBeholderScryDoubt".utf8)

    public static func hash(password: [UInt8], salt: [UInt8], cost: Int = 10) -> [UInt8] {
        precondition(salt.count == 16, "bcrypt salt must be 16 bytes")
        precondition(cost >= 4 && cost <= 31, "bcrypt cost must be 4-31")

        var key = password
        if !key.contains(0) { key.append(0) }

        var bf = Blowfish()
        bf.expandKey(key, salt: salt)

        let rounds = 1 << cost
        for _ in 0..<rounds {
            bf.expandKeyOnly(key)
            bf.expandKeyOnly(salt)
        }

        var words = stride(from: 0, to: ciphertext.count, by: 4).map { i -> UInt32 in
            var w: UInt32 = 0
            for k in 0..<4 where i + k < ciphertext.count {
                w = (w << 8) | UInt32(ciphertext[i + k])
            }
            return w
        }

        for _ in 0..<64 {
            var i = 0
            while i < words.count - 1 {
                var left = words[i]
                var right = words[i + 1]
                bf.encrypt(&left, &right)
                words[i] = left
                words[i + 1] = right
                i += 2
            }
        }

        var result = [UInt8]()
        for w in words {
            result.append(UInt8((w >> 24) & 0xFF))
            result.append(UInt8((w >> 16) & 0xFF))
            result.append(UInt8((w >> 8) & 0xFF))
            result.append(UInt8(w & 0xFF))
        }
        return Array(result.prefix(23))
    }

    public static func encodeSalt(_ bytes: [UInt8]) -> String {
        bcryptBase64Encode(bytes)
    }

    public static func hashString(password: String, salt: [UInt8], cost: Int = 10) -> String {
        let passwordBytes = Array(password.utf8)
        let hashBytes = hash(password: passwordBytes, salt: salt, cost: cost)
        let saltStr = bcryptBase64Encode(salt)
        let hashStr = bcryptBase64Encode(hashBytes)
        return "$2y$\(String(format: "%02d", cost))$\(saltStr)\(hashStr)"
    }

    public static func bcryptBase64Decode(_ string: String) -> [UInt8] {
        var lookup = [UInt8: UInt8]()
        for (i, c) in bcryptBase64Chars.enumerated() {
            lookup[c] = UInt8(i)
        }

        let chars = Array(string.utf8)
        var result = [UInt8]()
        var i = 0
        while i < chars.count {
            guard let c0 = lookup[chars[i]] else { break }
            guard i + 1 < chars.count, let c1 = lookup[chars[i + 1]] else { break }
            result.append((c0 << 2) | (c1 >> 4))

            guard i + 2 < chars.count, let c2 = lookup[chars[i + 2]] else { break }
            result.append(((c1 & 0x0F) << 4) | (c2 >> 2))

            guard i + 3 < chars.count, let c3 = lookup[chars[i + 3]] else { break }
            result.append(((c2 & 0x03) << 6) | c3)

            i += 4
        }
        return result
    }

    public static func bcryptBase64Encode(_ data: [UInt8]) -> String {
        var result = [UInt8]()
        var i = 0
        while i < data.count {
            let b0 = data[i]
            result.append(bcryptBase64Chars[Int(b0 >> 2)])

            if i + 1 < data.count {
                let b1 = data[i + 1]
                result.append(bcryptBase64Chars[Int((b0 & 0x03) << 4 | (b1 >> 4))])

                if i + 2 < data.count {
                    let b2 = data[i + 2]
                    result.append(bcryptBase64Chars[Int((b1 & 0x0f) << 2 | (b2 >> 6))])
                    result.append(bcryptBase64Chars[Int(b2 & 0x3f)])
                } else {
                    result.append(bcryptBase64Chars[Int((b1 & 0x0f) << 2)])
                }
            } else {
                result.append(bcryptBase64Chars[Int((b0 & 0x03) << 4)])
            }
            i += 3
        }
        return String(bytes: result, encoding: .ascii)!
    }
}
