import Foundation

/// Small, dependency-free helpers for the portal's server-rendered pages.
enum HTMLText {
    struct Match { let range: Range<String.Index>; let groups: [String] }
    static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (1..<max(result.numberOfRanges, 1)).map { i in Range(result.range(at: i), in: text).map { String(text[$0]) } ?? "" }
            return Match(range: range, groups: groups)
        }
    }
    static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decode(stripped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func decode(_ text: String) -> String {
        var result = text
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&#x2B;", "+"), ("&#x2F;", "/")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        // Remaining numeric entities, decimal and hex, rebuilt into a new string.
        var output = ""; var rest = Substring(result)
        while let start = rest.range(of: "&#") {
            output += rest[..<start.lowerBound]
            let after = rest[start.upperBound...]
            if let semicolon = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semicolon) <= 8 {
                let code = after[..<semicolon]
                let value = code.lowercased().hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code, radix: 10)
                if let value, let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar)); rest = after[after.index(after: semicolon)...]; continue
                }
            }
            output += "&#"; rest = after
        }
        output += rest
        // Last, so an escaped entity ("&amp;lt;") comes out as written ("&lt;") rather than decoded twice.
        result = output.replacingOccurrences(of: "&amp;", with: "&")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
