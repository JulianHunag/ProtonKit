import Foundation

public enum KeyPassphrase {
    public static func compute(password: String, keySalt: String) -> String? {
        guard let saltData = Data(base64Encoded: keySalt) else { return nil }

        let encodedSalt = Bcrypt.bcryptBase64Encode(Array(saltData))
        let salt22 = String(encodedSalt.prefix(22))
        guard salt22.count == 22 else { return nil }
        let rawSalt = Array(Bcrypt.bcryptBase64Decode(salt22).prefix(16))
        guard rawSalt.count == 16 else { return nil }

        let hashBytes = Bcrypt.hash(password: Array(password.utf8), salt: rawSalt, cost: 10)
        let hashEncoded = Bcrypt.bcryptBase64Encode(hashBytes)
        return hashEncoded
    }
}
