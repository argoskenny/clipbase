import Foundation

enum TextRangeHelpers {
    static func normalize(_ ranges: [CopyableRange], content: String) -> [CopyableRange] {
        let contentLength = (content.replacingOccurrences(of: "\r\n", with: "\n") as NSString).length
        let sorted = ranges
            .filter { range in
                range.start >= 0 &&
                range.end <= contentLength &&
                range.start < range.end
            }
            .sorted { left, right in
                if left.start == right.start {
                    return left.end < right.end
                }
                return left.start < right.start
            }

        var merged: [CopyableRange] = []
        for range in sorted {
            guard var previous = merged.last else {
                merged.append(range)
                continue
            }

            if range.start <= previous.end {
                previous.end = max(previous.end, range.end)
                merged[merged.count - 1] = previous
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    static func copyableRange(forSelection selectedRange: NSRange, content: String) -> CopyableRange? {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n") as NSString
        let contentLength = normalized.length
        guard contentLength > 0 else { return nil }

        let boundedLocation = max(0, min(selectedRange.location, contentLength))
        let boundedEnd = max(0, min(selectedRange.location + selectedRange.length, contentLength))
        var start = min(boundedLocation, boundedEnd)
        var end = max(boundedLocation, boundedEnd)

        while start < end, isWhitespace(normalized.character(at: start)) {
            start += 1
        }
        while end > start, isWhitespace(normalized.character(at: end - 1)) {
            end -= 1
        }

        return start < end ? CopyableRange(start: start, end: end) : nil
    }

    static func substring(_ content: String, in range: CopyableRange) -> String {
        let nsString = content.replacingOccurrences(of: "\r\n", with: "\n") as NSString
        let contentLength = nsString.length
        let start = max(0, min(range.start, contentLength))
        let end = max(0, min(range.end, contentLength))
        guard start < end else { return "" }
        return nsString.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isWhitespace(_ codeUnit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(codeUnit)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
