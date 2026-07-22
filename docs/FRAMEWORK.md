# Writing tests with Quick and Nimble

How we structure specs across the Swift side of these projects (`xctidy`
itself, [`zouk`](https://github.com/woodie/zouk), and
[`next-caltrain-swift`](https://github.com/woodie/next-caltrain-swift)) --
context/lifecycle conventions and mocking/stubbing patterns. Examples
below use a generic `Calculator`/`WeatherClient` rather than any one
project's real domain types, so the pattern reads the same regardless of
which of these apps you're actually working in; each section points at
the real file to read for the fuller version. For file-organization
conventions specific to `xctidy` (one `describe` per file, `swift test
--filter`'s Quick limitations), see the README's
[Writing tests](../README.md#writing-tests) section instead -- this doc
is about what goes *inside* a spec, not how specs are laid out on disk.

All three projects use [Quick](https://github.com/Quick/Quick) for
structure (`describe`/`context`/`it`, `beforeEach`/`afterEach`) and
[Nimble](https://github.com/Quick/Nimble) for matchers (`expect(x).to(equal(y))`).
The Go side of this pairing ([`gorderly`](https://github.com/woodie/gorderly),
[`expect`](https://github.com/woodie/expect)) follows the same shape with
different tools -- see `gorderly`'s own
[docs/FRAMEWORK.md](https://github.com/woodie/gorderly/blob/main/docs/FRAMEWORK.md)
if you're working on that side instead.

## Nesting context so it's available to every sub-test

`beforeEach` closures run fresh before each `it`, from the outermost
`describe` inward, so state set up at a given nesting level is visible to
every `it` (and every nested `context`) beneath it. This is the whole
mechanism -- there's no separate "shared context" feature to learn, just
where you place the closure.

```swift
describe("Calculator") {
    var calculator: Calculator!
    beforeEach {
        calculator = Calculator()
    }

    describe("#add(_:to:)") {
        context("adding two positive numbers") {
            var result: Int!
            beforeEach {
                result = calculator.add(2, to: 3)
            }

            it("returns the sum") {
                expect(result).to(equal(5))
            }
        }
    }
}
```

`calculator` is built once per `it` at the top of the file, and every
nested `describe`/`context` below can read it without redeclaring or
re-threading it through arguments. See `next-caltrain-swift`'s
`Tests/CaltrainServiceSpec.swift` for this exact shape used against a
real routing algorithm, with a `service` built the same way at the top.

### `justBeforeEach`: separate "what varies" from "the action under test"

When every `context` under a `describe` sets up different inputs but then
needs to run the *same* action against whatever those inputs were, put the
action in a `justBeforeEach` at the parent level -- it runs after every
`beforeEach` at every nesting level has finished, so it always sees the
leaf context's own setup:

```swift
describe("#divide(_:by:)") {
    var numerator: Int!
    var denominator: Int!
    var result: Int!
    justBeforeEach {
        result = calculator.divide(numerator, by: denominator)
    }

    context("dividing evenly") {
        beforeEach { numerator = 10; denominator = 2 }
        it("returns the quotient") { expect(result).to(equal(5)) }
    }

    context("dividing with a remainder") {
        beforeEach { numerator = 7; denominator = 2 }
        it("truncates toward zero") { expect(result).to(equal(3)) }
    }
}
```

Each `context` only has to state what's different about it (`numerator`/
`denominator`); the actual call under test is written once. `zouk`'s
`Tests/ZoukKitTests/ScanClientSpec.swift` uses the same split for async
work -- a `justBeforeEach` awaits the call under test, sitting above
several `context`s that each configure a different fake-server response.

### `afterEach` for cleanup

Anything a `beforeEach` creates outside the process (a temp directory, a
global override) should get torn down in a matching `afterEach`, so one
spec's state can't leak into the next:

```swift
afterEach { try? FileManager.default.removeItem(at: tempDirectory) }
```

See also the stubbing example below, where `afterEach` resets a global
override rather than a filesystem path.

## Mocking and stubbing

### Protocol-based fakes

When a type talks to the network (or any other side effect), depend on a
protocol rather than a concrete type, so tests can substitute a fake:

```swift
protocol HTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var dataHandler: ((URL) throws -> (Data, URLResponse))?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        guard let dataHandler else { throw URLError(.unknown) }
        return try dataHandler(url)
    }
}
```

Each `context` then configures just the handler it needs, right where the
behavior it's testing is being described:

```swift
context("when the server responds with 200 and a valid payload") {
    beforeEach {
        fakeClient.dataHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (validPayload, response)
        }
    }
    it("decodes the response") { /* ... */ }
}

context("when the server responds with a non-2xx status") {
    beforeEach {
        fakeClient.dataHandler = { url in
            (Data(), HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    it("throws a server error") { /* ... */ }
}
```

The fake conforms to the real protocol, so the type signature under test
never changes between production and test code -- only which concrete
type gets passed in. This mirrors `zouk`'s real
`Tests/ZoukKitTests/FakeHTTPClient.swift`/`ScanClientSpec.swift` almost
exactly; see those files for the fuller version, including download and
delete handlers.

### Stubbing with a debug override (no protocol needed)

Not everything worth stubbing has (or needs) a protocol. If a type
depends on "what time is it right now," rather than threading a `Clock`
protocol through every call site, a settable override reserved for tests
can be simpler:

```swift
Clock.debugOverrideNow = Date(timeIntervalSince1970: 0)
```

This is a smaller, more invasive tool than a protocol-based fake -- it
works because there's exactly one production caller of the real clock and
the override is a single global, not a dependency graph -- but it keeps a
whole spec file's worth of time-dependent tests deterministic without a
constructor-injection refactor. Because it's global state, every spec
that uses it resets it in `afterEach`:

```swift
afterEach { Clock.debugOverrideNow = nil }
```

so a later spec file never inherits a stale override. `next-caltrain-swift`'s
`GoodTimes.debugOverrideMinutes`/`debugOverrideDotw` (see
`Tests/TripViewModelSpec.swift`) is the real version of this same idea.

### Data builders for realistic fixtures

Neither a mock nor a stub, but adjacent: when a domain type's real
constructor takes more setup than any individual test cares about, a
small builder lets each spec say only what varies and get a consistent,
realistic default for everything else:

```swift
let order = OrderFixtures.order {
    $0.items = [.init(sku: "WIDGET-1", quantity: 2)]
}
```

`next-caltrain-swift`'s `Tests/SpecFixtures.swift` is the real version of
this idea -- a builder (`SpecFixtures.schedule { ... }`) for constructing
a realistic train schedule without every spec hand-rolling the full
station/time-table structure.

### Regression tests double as documentation

When a spec exists specifically to pin down a bug that already happened,
say so in a comment right at the setup, not just in the commit message:

```swift
context("when a cached file's size no longer matches what's expected") {
    // Regression test for the stale-cache bug.
    ...
}
```

Anyone reading the spec later knows immediately this isn't a hypothetical
edge case -- removing it silently would reintroduce a real, previously-
shipped bug. See `zouk`'s `ScanClientSpec.swift` for a real one of these.

## `xctidy`'s own tests

`Tests/XctidyKitTests/EngineSpec.swift` follows the same conventions
against `xctidy`'s own `Engine` type -- nested `context`s for each output
style (classic/spec/doc/vitest), each just calling `engine.feedLine(...)`
and asserting on `engine.finish()`, with no mocking needed since `Engine`
has no external dependencies to fake. Good example to read if you want the
context-nesting patterns above without the added complexity of async code
or protocol fakes.
