import Foundation

enum HTMLSanitizer {
    static func sanitize(_ html: String) -> String {
        var result = html

        let dangerousPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<iframe[^>]*>[\\s\\S]*?</iframe>",
            "<object[^>]*>[\\s\\S]*?</object>",
            "<embed[^>]*>",
            "<form[^>]*>[\\s\\S]*?</form>",
            "\\son\\w+\\s*=\\s*\"[^\"]*\"",
            "\\son\\w+\\s*=\\s*'[^']*'",
            "javascript:",
        ]

        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        return result
    }
}
