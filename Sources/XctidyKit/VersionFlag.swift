// Pulled out of main.swift so it's unit-testable -- main.swift's top-level script code isn't reachable from XctidyKitTests. See VersionFlagSpec and docs/COMMENTS.md.

/// Whether `args` requests version reporting; must be checked before the stdin-reading loop starts, or a bare `xctidy --version` would hang waiting for piped input that never arrives.
public func wantsVersion(_ args: [String]) -> Bool {
    args.contains("--version") || args.contains("-v")
}
