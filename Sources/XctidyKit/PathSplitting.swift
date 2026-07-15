import Foundation

// MARK: - Dictionary-based comma disambiguation

// Builds the atom set from spec files, then tries to decompose a flattened Quick name into a unique ", "-joined sequence of atoms, falling back to a heuristic split if ambiguous. See docs/COMMENTS.md.

public func unescapeSwiftLiteral(_ raw: String) -> String {
    var out = ""
    let chars = Array(raw)
    var i = 0
    while i < chars.count {
        let chr = chars[i]
        if chr == "\\", i + 1 < chars.count {
            switch chars[i + 1] {
            case "n": out.append("\n")
            case "t": out.append("\t")
            default: out.append(chars[i + 1])
            }
            i += 2
        } else {
            out.append(chr)
            i += 1
        }
    }
    return out
}

/// Recursively scans every `*.swift` file under `specsDir` for describe/context/it string literals; must be recursive since SwiftPM nests each target's specs one level below `Tests/`. See docs/COMMENTS.md.
public func loadKnownAtoms(specsDir: String) -> Set<String> {
    var atoms = Set<String>()
    let fmr = FileManager.default
    guard let entries = try? fmr.subpathsOfDirectory(atPath: specsDir) else {
        return atoms
    }
    for file in entries.filter({ $0.hasSuffix(".swift") }).sorted() {
        let path = (specsDir as NSString).appendingPathComponent(file)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        for m in Matchers.atomCall.matches(in: text, range: range) {
            let raw = nsText.substring(with: m.range(at: 1))
            atoms.insert(unescapeSwiftLiteral(raw))
        }
    }
    return atoms
}

func findDecompositions(_ name: String, atoms: Set<String>, limit: Int = 2) -> [[String]] {
    if atoms.isEmpty { return [] }
    let byLen = atoms.sorted { $0.count > $1.count }
    let chars = Array(name)
    let n = chars.count
    var results: [[String]] = []

    func rec(_ start: Int, _ path: inout [String]) {
        if results.count >= limit { return }
        if start == n {
            results.append(path)
            return
        }
        for atom in byLen {
            if results.count >= limit { return }
            if atom.isEmpty { continue }
            let atomChars = Array(atom)
            let end = start + atomChars.count
            if end > n { continue }
            if Array(chars[start..<end]) != atomChars { continue }
            if end == n {
                path.append(atom)
                rec(end, &path)
                path.removeLast()
            } else if end + 2 <= n, chars[end] == ",", chars[end + 1] == " " {
                path.append(atom)
                rec(end + 2, &path)
                path.removeLast()
            }
        }
    }

    var path: [String] = []
    rec(0, &path)
    return results
}

/// Splits only at top-level (paren-depth 0) `", "`; keeps parenthetical asides like "(San Francisco to San Jose Diridon)" intact. See docs/COMMENTS.md.
func splitHeuristic(_ name: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var depth = 0
    let chars = Array(name)
    var i = 0
    let n = chars.count
    while i < n {
        let chr = chars[i]
        if chr == "(" {
            depth += 1
            current.append(chr)
            i += 1
        } else if chr == ")" {
            depth = max(depth - 1, 0)
            current.append(chr)
            i += 1
        } else if depth == 0, i + 1 < n, chars[i] == ",", chars[i + 1] == " " {
            parts.append(current)
            current = ""
            i += 2
        } else {
            current.append(chr)
            i += 1
        }
    }
    parts.append(current)
    return parts
}

public func splitPath(_ name: String, atoms: Set<String>) -> [String] {
    let decompositions = findDecompositions(name, atoms: atoms)
    if decompositions.count == 1 {
        return decompositions[0]
    }
    return splitHeuristic(name)
}
