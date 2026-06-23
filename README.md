# xcbeautify-fd

Bring [RSpec](https://github.com/rspec/rspec)'s "format documentation" (`-fd`) output to `xcodebuild test`, for projects using [Quick](https://github.com/Quick/Quick)/[Nimble](https://github.com/Quick/Nimble).

`xcbeautify-fd` reads xcodebuild's raw test output directly -- the same textual protocol [xcpretty](https://github.com/xcpretty/xcpretty) and [xcbeautify](https://github.com/cpisciotta/xcbeautify) both parse -- so it works standalone, with no dependency on either tool being installed. It's the sibling project to [ginkgo-fd](https://github.com/woodie/ginkgo-fd), which does the same thing for Go's Ginkgo.

## Why a separate tool

Quick promotes the full `describe`/`context`/`it` text to the XCTest selector name by joining each level with `", "`. That's fine until the prose itself contains a comma -- `it("computes tomorrow as Sunday (0), wrapping the week")` -- at which point a naive split on `", "` can't tell a nesting boundary from a comma in someone's sentence.

`xcbeautify-fd` resolves this by cross-referencing the literal `describe(...)`/`context(...)`/`it(...)` strings in your `Tests/*.swift` files. If there's exactly one way to decompose a flattened name into known atoms, it uses that; otherwise it falls back to a paren-depth-aware split. Because it parses the raw `error:` line directly, failing tests fold cleanly into the tree with their message and `file:line`, instead of being shown as flat output. This is the underlying engine that was originally built and validated as a [test_formatter.py post-processor](https://github.com/woodie/next-caltrain-swift) for xcbeautify's output; this tool removes that dependency by parsing xcodebuild directly.

## Installation

Build locally with Swift Package Manager:

```
git clone https://github.com/woodie/xcbeautify-fd.git
cd xcbeautify-fd
swift build -c release
cp .build/release/xcbeautify-fd /usr/local/bin/
```

## Usage

Pipe `xcodebuild test` straight into it, the same way you'd pipe into xcpretty or xcbeautify. Pass the path to your `Tests` directory (containing your `describe`/`context`/`it` spec files) as the one argument, so the comma-disambiguation dictionary can be built:

```
xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15' | xcbeautify-fd Tests
```

If no path is given, it looks in the current directory.

Sample output:

```
NextCaltrainTests.xctest

GoodTimesSpec
  GoodTimes
    when 'today' is fixed via debugOverrideDotw
      and today is Saturday (6)
        computes tomorrow as Sunday (0), wrapping the week

CaltrainServiceSpec
  CaltrainService
    #routes(from:to:scheduleType:)
      for a direct diesel trip (Morgan Hill to Gilroy)
        is not a transfer, since both endpoints are South County
      for a direct electric trip (San Francisco to San Jose Diridon)
        is not a transfer (FAILED - 1)
    #nextIndex(trips:minutes:)
      when given an empty trip list
        returns nil (SKIPPED)

Failures:

  1) CaltrainService #routes(from:to:scheduleType:) for a direct electric trip (San Francisco to San Jose Diridon) is not a transfer
     XCTAssertFalse failed - expected false, got true
     # /path/to/Tests/CaltrainServiceSpec.swift:55
```

Build-phase noise (compiles, links, codesign) is suppressed for a clean test-only view. Any line containing `error:` is always passed through verbatim, so a real build failure is never hidden.

## Status

This is a proof-of-concept built to demonstrate that an RSpec-`-fd`-style formatter can work directly against xcodebuild's raw output, ahead of proposing it as a built-in mode for xcbeautify -- mirroring [ginkgo-fd's upstream contribution to Ginkgo](https://github.com/onsi/ginkgo/pull/1670).
