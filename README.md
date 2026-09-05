# ProjectGoldenEagle

Single-player top-down tank action game for iPhone (landscape), then iPad and
macOS. Design and planning documents live at the repository root and in
`docs/`; start with `DOCUMENT_INDEX.md`.

## Pinned toolchain and destinations (M0)

| Item | Pinned value |
| --- | --- |
| Xcode | 26.6 (17F113) |
| Swift toolchain | 6.3 (language mode 6, `SWIFT_STRICT_CONCURRENCY=complete`) |
| iOS deployment target | 17.0 |
| Xcode scheme | `SparkTread` |
| CI simulator destination | `platform=iOS Simulator,name=iPhone 17` |
| Minimum-supported-device floor | 390×844-point class (ADR-0004); legibility gates run on a physical floor-class iPhone |

## Project generation

The Xcode project is generated — do not edit `SparkTread.xcodeproj`
by hand; change `project.yml` and regenerate:

```sh
brew install xcodegen   # once
xcodegen generate
```

## Build, test, run

```sh
# Full non-interactive gate (architecture check, content validation,
# package tests, scheme tests). CI (.github/workflows/ci.yml) runs the same
# script once a GitHub remote is configured:
sh Scripts/ci.sh

# Content validation alone (Content/Schemas/id_registry.json is the
# canonical stable-ID registry, GE-020):
swift run content-validator Content

# Individual steps:
sh Scripts/check-architecture.sh
swift test
xcodebuild test -project SparkTread.xcodeproj -scheme SparkTread \
    -destination 'platform=iOS Simulator,name=iPhone 17'

# Run in the simulator:
xcodebuild build -project SparkTread.xcodeproj -scheme SparkTread \
    -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData
xcrun simctl boot "iPhone 17"
xcrun simctl install "iPhone 17" .build/DerivedData/Build/Products/Debug-iphonesimulator/SparkTread.app
xcrun simctl launch "iPhone 17" io.icell.sparktread
```

## Layering (§14, D-017)

- `Sources/GameCore/` — authoritative rules and state; imports nothing (not
  even Foundation).
- `Sources/GameApplication/` — workflows and use cases; imports only GameCore.
- `Sources/AppleAdapters/` — SwiftUI, SpriteKit, input, audio, persistence,
  platform; depends inward.
- `Sources/GoldenEagleApp/` — app entry target (generated project); wires the
  composition root only.

`Scripts/check-architecture.sh` enforces the forbidden-dependency rules.

## Pixel art delivery (SparkTreadPixel submodule)

The art lives in the `Vendor/SparkTreadPixel` git submodule
(github.com/iCell/SparkTreadPixel) — clone with `--recursive` or run
`git submodule update --init`. The app target references the submodule's
17 `.atlas` folders and `pixel_assets.json` directly; the runtime adapters
in `Sources/AppleAdapters/Presentation/Pixel/` are synced copies of the
submodule's `Runtime/` (diff before upgrading). The app icon also comes
from the submodule (copied into the asset catalog).
Reference docs live in `docs/pixel/`. The app root is the M1
`MovementLabView` (touch joystick, keyboard arrows/WASD, controller D-pad);
launch env `MOVEMENT_LAB_AUTODRIVE=1` runs a scripted demo drive. The
delivery's own preview renders remain in the source package's `Previews/`.
