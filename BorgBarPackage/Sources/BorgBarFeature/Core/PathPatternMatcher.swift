import Foundation
import Darwin

enum PathPatternMatcher {
    static func isCoveredByDefaultPatterns(path: String, defaultPatterns: [String]) -> Bool {
        let normalizedPath = NSString(string: path).standardizingPath
        let probeChild = normalizedPath.hasSuffix("/") ? "\(normalizedPath)__borgbar_probe__" : "\(normalizedPath)/__borgbar_probe__"
        for pattern in defaultPatterns {
            if matches(path: normalizedPath, pattern: pattern) || matches(path: probeChild, pattern: pattern) {
                return true
            }
        }
        return false
    }

    static func matches(path: String, pattern: String) -> Bool {
        path.withCString { pathCStr in
            pattern.withCString { patternCStr in
                fnmatch(patternCStr, pathCStr, 0) == 0
            }
        }
    }
}
