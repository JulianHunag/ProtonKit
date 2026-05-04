import Foundation
import CryptoKit

public enum ExpandHash {
    public static func hash(_ data: Data) -> Data {
        var result = Data(capacity: 256)
        for i: UInt8 in 0..<4 {
            var input = data
            input.append(i)
            let digest = SHA512.hash(data: input)
            result.append(contentsOf: digest)
        }
        return result.prefix(256)
    }
}
