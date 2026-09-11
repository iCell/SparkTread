# SparkTread

Single-player tank-battle arcade game for iPhone (landscape first, iPad/macOS later). Swift + SpriteKit + SwiftUI. A modern remake informed by reverse-analysis of 决战坦克 v1.2.2.

## Model-usage policy

Do the **analysis, orchestration, and verification** in this project yourself. For **purely execution** tasks — mechanical file creation, boilerplate, applying an already-specified change across files — delegate to an Opus subagent (Agent tool with `model: "opus"`), then verify its output yourself (build, test, review the diff).

## Authority order (when documents conflict)

1. Accepted ADRs in `docs/decisions/`
2. `PRODUCT_IMPLEMENTATION_PLAN.md`
3. `PROJECT_MASTER_SUMMARY_ZH.md`
4. Automated tests and pinned content schemas
5. `GAME_RULES.md` reference facts (its "current implementation" notes are descriptive and its §18 deviation list is a proposal, not authority)
6. Everything else

Key accepted ADRs: 1 cell = 1024 subunits (ADR-0001); `PlayerCommand` is the only external input contract (ADR-0002); full-screen arena and the 390-point device floor (ADR-0004); the pixel delivery satisfies the style lock (ADR-0008) and the universal arena is pinned at 56×27 (ADR-0009); owner combat rules and fort ring (ADR-0010); reference SFX (ADR-0011); results table and stage-clear bonuses (ADR-0012); no danger telegraph, foliage fire, Training Arena (ADR-0017). ADR-0013…0016 are still Proposed.

## Architecture (from plan §13–14)

- `Sources/GameCore/` — pure Swift deterministic simulation. MUST NOT import SpriteKit, SwiftUI, UIKit/AppKit, GameKit, GameController, AVFoundation, Foundation file/clock APIs, or use global RNG. Integer/fixed-point authoritative state only — **no floats for positions, cooldowns, damage, or RNG decisions**.
- `Sources/GameApplication/` — session flow, replay, content loading. Depends only on GameCore.
- `Sources/AppleAdapters/` — SpriteKit/SwiftUI/input/audio/persistence. Depends inward. Composition happens only in `Bootstrap/` and the app entry.
- Simulation: 60 Hz fixed tick, ordered tick pipeline (plan §13.6), named RNG streams `ai`/`spawn`/`drop`, arena 56×27 cells (ADR-0009), 1024 subunits per cell, origin top-left, tanks 2×2 cells.
- Entity processing order is explicit (ascending entity id); never rely on Dictionary/Set iteration order.
- `SKAction`, `Timer`, and callbacks are presentation tools, never simulation clocks.

## Art assets

Use the `Vendor/SparkTreadPixel` submodule exclusively: its `.atlas` folders plus `Metadata/pixel_assets.json`; the runtime adapters live in `Sources/AppleAdapters/Presentation/Pixel/`. Integration steps: `docs/pixel/SPRITEKIT_USAGE_ZH.md`. Do not bundle `Current/`, `Tools/`, `Previews/`, or QA JSON into the app. Do not generate new assets without an explicit request. Audio assets are tied to `Tools/audio_manifest.json` and checked by `Scripts/check-audio.sh`.

## Commands

- Headless build & test: `swift build && swift test`.
- The single non-interactive gate is `sh Scripts/ci.sh`: architecture check, `swift run content-validator Content`, audio check, `swift test`, `xcodegen generate`, `xcodebuild test`, smoke render.
- Device install: `sh Scripts/deploy-device.sh` (needs an unlocked, connected iPhone).
- iOS app project: generate with `xcodegen generate` from `project.yml` (requires Xcode + xcodegen installed), scheme `SparkTread`.

## Conventions

- Changing a fixed decision (plan §4) requires an ADR in `docs/decisions/ADR-NNNN-short-name.md` — never silently reinterpret one.
- V1 is single-player only: no networking abstractions, no dormant multiplayer sockets or UI.
- Gameplay rules never live in HUD/animation/audio/scene code.
- Comments explain constraints and intent, not line-by-line paraphrase.
