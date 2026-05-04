import Foundation

public enum ModulusParser {
    public static func decode(_ signedMessage: String) throws -> Data {
        let lines = signedMessage.components(separatedBy: .newlines)

        var inBody = false
        var base64Lines = [String]()
        for line in lines {
            if line.isEmpty && !inBody {
                inBody = true
                continue
            }
            if line.hasPrefix("-----BEGIN PGP SIGNATURE") {
                break
            }
            if inBody {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    base64Lines.append(trimmed)
                }
            }
        }

        let base64String = base64Lines.joined()
        guard let data = Data(base64Encoded: base64String) else {
            throw SRPError.invalidModulusFormat
        }
        return data
    }
}
