import Foundation

public enum PasswordHash {
    public static func hash(password: Data, salt: Data, modulus: Data, version: Int) throws -> Data {
        switch version {
        case 3, 4:
            return try hashV3(password: password, salt: salt, modulus: modulus)
        case 1, 2:
            return try hashV1(password: password, salt: salt, modulus: modulus)
        case 0:
            return hashV0(password: password, salt: salt)
        default:
            throw SRPError.unsupportedAuthVersion(version)
        }
    }

    private static func hashV3(password: Data, salt: Data, modulus: Data) throws -> Data {
        var saltWithSuffix = Array(salt)
        saltWithSuffix.append(contentsOf: Array("proton".utf8))
        let encodedSalt = Bcrypt.bcryptBase64Encode(saltWithSuffix)

        let salt22 = String(encodedSalt.prefix(22))
        guard salt22.count == 22 else { throw SRPError.invalidSalt }
        let rawSalt = Array(Bcrypt.bcryptBase64Decode(salt22).prefix(16))
        guard rawSalt.count == 16 else { throw SRPError.invalidSalt }

        let passwordBytes = Array(password)
        let hashBytes = Bcrypt.hash(password: passwordBytes, salt: rawSalt, cost: 10)
        let hashEncoded = Bcrypt.bcryptBase64Encode(hashBytes)
        let fullBcryptString = "$2y$10$\(salt22)\(hashEncoded)"

        var combined = Data(fullBcryptString.utf8)
        combined.append(modulus)
        return ExpandHash.hash(combined)
    }

    private static func hashV1(password: Data, salt: Data, modulus: Data) throws -> Data {
        var combined = Data()
        combined.append(password)
        combined.append(salt)
        combined.append("proton".data(using: .utf8)!)
        return ExpandHash.hash(combined)
    }

    private static func hashV0(password: Data, salt: Data) -> Data {
        var combined = Data()
        combined.append(password)
        combined.append(salt)
        return ExpandHash.hash(combined)
    }
}
