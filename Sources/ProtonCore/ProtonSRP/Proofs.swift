import Foundation
import BigInt

public struct SRPProofs {
    public let clientEphemeral: Data
    public let clientProof: Data
    public let expectedServerProof: Data
}

public enum SRPError: Error {
    case invalidModulusSize
    case multiplierOutOfBounds
    case serverEphemeralOutOfBounds
    case unsupportedAuthVersion(Int)
    case invalidSalt
    case invalidModulusFormat
    case invalidServerEphemeral
}

enum SRPProofGenerator {
    private static let modulusBitLength = 2048
    private static let modulusByteLength = modulusBitLength / 8 // 256

    static func generateProofs(
        modulusBytes: Data,
        hashedPassword: Data,
        serverEphemeralBytes: Data
    ) throws -> SRPProofs {
        let l = modulusBitLength
        let byteLen = modulusByteLength
        let generator = BigUInt(2)

        let modulus = fromLittleEndian(modulusBytes)
        let hashed = fromLittleEndian(hashedPassword)
        let serverEphemeral = fromLittleEndian(serverEphemeralBytes)
        let modulusMinusOne = modulus - 1

        guard modulus.bitWidth >= l else {
            throw SRPError.invalidModulusSize
        }

        let multiplier = fromLittleEndian(
            ExpandHash.hash(toLittleEndian(generator, length: byteLen) + modulusBytes)
        ) % modulus

        guard multiplier > 1 && multiplier < modulusMinusOne else {
            throw SRPError.multiplierOutOfBounds
        }
        guard serverEphemeral > 1 && serverEphemeral < modulusMinusOne else {
            throw SRPError.serverEphemeralOutOfBounds
        }

        var clientSecret: BigUInt
        var clientEphemeral: BigUInt
        var scramblingParam: BigUInt

        repeat {
            repeat {
                clientSecret = BigUInt.randomInteger(lessThan: modulusMinusOne)
            } while clientSecret <= BigUInt(l * 2)

            clientEphemeral = generator.power(clientSecret, modulus: modulus)
            let u_input = toLittleEndian(clientEphemeral, length: byteLen) + toLittleEndian(serverEphemeral, length: byteLen)
            scramblingParam = fromLittleEndian(ExpandHash.hash(u_input))
        } while scramblingParam == 0

        let gx = generator.power(hashed, modulus: modulus)
        var subtracted: BigInt = BigInt(serverEphemeral) - BigInt((multiplier * gx) % modulus)
        if subtracted < 0 {
            subtracted += BigInt(modulus)
        }
        let base = BigUInt(subtracted)
        let exponent = (BigUInt(scramblingParam) * hashed + clientSecret) % modulusMinusOne
        let sharedSession = base.power(exponent, modulus: modulus)

        let ceBytes = toLittleEndian(clientEphemeral, length: byteLen)
        let seBytes = toLittleEndian(serverEphemeral, length: byteLen)
        let ssBytes = toLittleEndian(sharedSession, length: byteLen)

        let clientProof = ExpandHash.hash(ceBytes + seBytes + ssBytes)
        let serverProof = ExpandHash.hash(ceBytes + clientProof + ssBytes)

        return SRPProofs(
            clientEphemeral: ceBytes,
            clientProof: clientProof,
            expectedServerProof: serverProof
        )
    }

    private static func toLittleEndian(_ value: BigUInt, length: Int) -> Data {
        var bytes = value.serialize() // big-endian
        bytes.reverse() // now little-endian
        if bytes.count < length {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: length - bytes.count))
        }
        return Data(bytes.prefix(length))
    }

    private static func fromLittleEndian(_ data: Data) -> BigUInt {
        var bytes = Array(data)
        bytes.reverse() // back to big-endian
        return BigUInt(Data(bytes))
    }
}
