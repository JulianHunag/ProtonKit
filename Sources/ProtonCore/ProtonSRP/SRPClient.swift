import Foundation

public struct SRPAuthResult {
    let clientEphemeral: String // base64
    let clientProof: String     // base64
    let expectedServerProof: String // base64
}

public enum SRPClient {
    public static func generateSRP(
        password: String,
        authInfo: AuthInfoResponse
    ) throws -> SRPAuthResult {
        let modulus = try ModulusParser.decode(authInfo.modulus)

        guard let serverEphemeral = Data(base64Encoded: authInfo.serverEphemeral) else {
            throw SRPError.invalidServerEphemeral
        }
        guard let salt = Data(base64Encoded: authInfo.salt) else {
            throw SRPError.invalidSalt
        }

        let passwordData = Data(password.utf8)
        let hashedPassword = try PasswordHash.hash(
            password: passwordData,
            salt: salt,
            modulus: modulus,
            version: authInfo.version
        )

        let proofs = try SRPProofGenerator.generateProofs(
            modulusBytes: modulus,
            hashedPassword: hashedPassword,
            serverEphemeralBytes: serverEphemeral
        )

        return SRPAuthResult(
            clientEphemeral: proofs.clientEphemeral.base64EncodedString(),
            clientProof: proofs.clientProof.base64EncodedString(),
            expectedServerProof: proofs.expectedServerProof.base64EncodedString()
        )
    }

    public static func verifyServerProof(_ serverProof: String, expected: String) -> Bool {
        guard let spData = Data(base64Encoded: serverProof),
              let exData = Data(base64Encoded: expected) else {
            return false
        }
        guard spData.count == exData.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(spData, exData) {
            result |= a ^ b
        }
        return result == 0
    }
}
