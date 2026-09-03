# SparkTread

Single-player tank-battle arcade game for iPhone (landscape first, iPad and macOS later).
Swift + SpriteKit + SwiftUI, with a pure deterministic simulation core: fixed 60 Hz tick,
integer/fixed-point authoritative state, named RNG streams, and a 48x27 cell arena.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/GameCore/` | Deterministic simulation. Imports nothing — not even Foundation. |
| `Sources/GameApplication/` | Session flow, replay, content loading. Depends on GameCore only. |
| `Sources/AppleAdapters/` | SpriteKit/SwiftUI presentation. Compiled by the Xcode app target, not by the package. |
| `App/` | SwiftUI entry point. |
| `Tools/ContentValidator/` | Offline content linter. |
| `Tests/` | Swift Testing suites plus shared fixtures. |
| `PixelProduction/` | Pixel art package: 17 `.atlas` folders, manifest, runtime adapters. |

## Headless (no Xcode required)

```sh
swift build
swift test
swift run ContentValidator path/to/stage.json [...]
```

`ContentValidator` prints `OK <path>` or `FAIL <path>: <what to fix>` per file and exits
non-zero if any file fails, so it drops straight into CI.

### Known toolchain gap: `swift test` needs extra flags without Xcode

Swift Command Line Tools 6.3 ship swift-testing under `Library/Developer/Frameworks`, but
SwiftPM passes that directory as `-I`/`-L` instead of `-F` and writes no matching runpath,
so a bare `swift test` cannot find the `Testing` module. Until a toolchain with Xcode is
installed, run:

```sh
CLT=$(xcode-select -p)
swift test \
  -Xswiftc -F -Xswiftc "$CLT/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib"
```

Plain `swift test` works unchanged once Xcode is installed. `swift build` is unaffected.

## iOS app

The `.xcodeproj` is generated, not committed. With Xcode and
[xcodegen](https://github.com/yonaskolb/XcodeGen) installed:

```sh
xcodegen generate
open SparkTread.xcodeproj
```

Then run the `SparkTread` scheme. It builds the app target from `App/`,
`Sources/AppleAdapters/`, and the PixelProduction runtime adapters, links the `GameCore`
and `GameApplication` package products, and bundles the atlases and sprite manifest.

## Where the rules live

- `CLAUDE.md` — working agreement, architecture constraints, authority order.
- `DOCUMENT_INDEX.md` — map of every planning document.
- `docs/decisions/` — accepted ADRs. These outrank the plan; changing a fixed decision
  requires a new ADR rather than a reinterpretation.

## Status

M0 scaffold. GameCore carries arena geometry, direction, entity id, subunit positions, tick
constants, and the deterministic RNG streams; GameApplication carries stage schema
validation. Rules, systems, AI, session, and replay are milestone placeholders.

The iOS app target is **unverified**: this machine has Swift Command Line Tools only, so
`project.yml`, the SwiftUI entry point, and `BootstrapScene` have never been compiled.
First task on a machine with Xcode is to generate the project and confirm the bootstrap
scene draws four pixel tanks.
