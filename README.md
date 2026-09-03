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
| Xcode scheme | `ProjectGoldenEagle` |
| CI simulator destination | `platform=iOS Simulator,name=iPhone 17` |
| Minimum-supported-device floor | 390×844-point class (ADR-0004); legibility gates run on a physical floor-class iPhone |

## Project generation

The Xcode project is generated — do not edit `ProjectGoldenEagle.xcodeproj`
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
xcodebuild test -project ProjectGoldenEagle.xcodeproj -scheme ProjectGoldenEagle \
    -destination 'platform=iOS Simulator,name=iPhone 17'

# Run in the simulator:
xcodebuild build -project ProjectGoldenEagle.xcodeproj -scheme ProjectGoldenEagle \
    -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData
xcrun simctl boot "iPhone 17"
xcrun simctl install "iPhone 17" .build/DerivedData/Build/Products/Debug-iphonesimulator/ProjectGoldenEagle.app
xcrun simctl launch "iPhone 17" vip.icell.ProjectGoldenEagle
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

## Pixel art delivery (PixelProduction)

`Resources/Pixel/` holds the PixelProduction delivery exactly per its
integration contract: the 17 `.atlas` folders, `pixel_assets.json`, and the
runtime adapters in `Sources/AppleAdapters/Presentation/Pixel/`
(`PixelArt.swift`, `PixelPresentation.swift` — presentation only, no rules).
Reference docs live in `docs/pixel/`. The current app root is
`PixelShowcaseView`: swipeable SpriteKit pages (battle arena, tank roster,
directions/equipment, item sheet, M0 grid) — a scripted art fixture for
review, not gameplay. Launch env `SHOWCASE_PAGE=0…4` preselects a page.
