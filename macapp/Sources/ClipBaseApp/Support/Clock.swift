import Foundation

enum Clock {
    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
