//
//  Version.swift
//  Dowey
//
//  Release numbers, compared part by part. Kept apart from the Updater so the
//  test bundle can compile it on its own, the way it does ZoneMath.
//

/// A dotted release number. Missing parts count as zero, so 1.5 == 1.5.0.
struct Version: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        // Empty pieces are kept so "1..3" fails rather than reading as 1.3.
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    var description: String { parts.map(String.init).joined(separator: ".") }
}
