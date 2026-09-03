# SparkTread

Single-player tank-battle arcade game for iPhone (landscape first, iPad/macOS later). Swift + SpriteKit + SwiftUI. A modern remake informed by reverse-analysis of 决战坦克 v1.2.2.

## Model-usage policy

As a Fable model, you do the **analysis, orchestration, and verification** in this project. For **purely execution** tasks — mechanical file creation, boilerplate, applying an already-specified change across files — delegate to an Opus subagent (Agent tool with `model: "opus"`), then verify its output yourself (build, test, review the diff).

## Authority order (when documents conflict)

1. Accepted ADRs in `docs/decisions/`
2. `PRODUCT_IMPLEMENTATION_PLAN.md`
3. `PROJECT_MASTER_SUMMARY_ZH.md`
4. Automated tests and pinned content schemas
5. `GAME_MECHANICS_SPEC.md` reference facts
6. Everything else

Key accepted ADRs: art direction is the pixel style delivered in `PixelProduction/` (ADR-0001, supersedes D-019/D-020); product/scheme name is **SparkTread** (ADR-0002); arena stays 48×27 with a revised functional legibility gate (ADR-0003).

## Architecture (from plan §13–14)

- `Sources/GameCore/` — pure Swift deterministic simulation. MUST NOT import SpriteKit, SwiftUI, UIKit/AppKit, GameKit, GameController, AVFoundation, Foundation file/clock APIs, or use global RNG. Integer/fixed-point authoritative state only — **no floats for positions, cooldowns, damage, or RNG decisions**.
- `Sources/GameApplication/` — session flow, replay, content loading. Depends only on GameCore.
- `Sources/AppleAdapters/` — SpriteKit/SwiftUI/input/audio/persistence. Depends inward. Composition happens only in `Bootstrap/` and the app entry.
- Simulation: 60 Hz fixed tick, ordered tick pipeline (plan §13.6), named RNG streams `ai`/`spawn`/`drop`, arena 48×27 cells, 1024 subunits per cell, origin top-left, tanks 2×2 cells.
- Entity processing order is explicit (ascending entity id); never rely on Dictionary/Set iteration order.
- `SKAction`, `Timer`, and callbacks are presentation tools, never simulation clocks.

## Art assets

Use `PixelProduction/` exclusively: 17 `.atlas` folders, `Metadata/pixel_assets.json` manifest, and the runtime adapters `PixelProduction/Runtime/PixelArt.swift` + `PixelPresentation.swift`. Integration steps: `PixelProduction/Docs/SPRITEKIT_USAGE_ZH.md`. Do not bundle `Current/`, `Tools/`, `Previews/`, or QA JSON into the app. Do not generate new assets without an explicit request.

## Commands

- Headless build & test (works without Xcode, CLT is enough): `swift build && ./scripts/test.sh`
  (`scripts/test.sh` wraps `swift test` with `-F`/rpath flags for the bundled Testing.framework — plain `swift test` fails to find the `Testing` module under Command Line Tools 6.3.1; with full Xcode either form works.)
- iOS app project: generate with `xcodegen generate` from `project.yml` (requires Xcode + xcodegen installed), scheme `SparkTread`.

## Conventions

- Changing a fixed decision (plan §4) requires an ADR in `docs/decisions/ADR-NNNN-short-name.md` — never silently reinterpret one.
- V1 is single-player only: no networking abstractions, no dormant multiplayer sockets or UI.
- Gameplay rules never live in HUD/animation/audio/scene code.
- Comments explain constraints and intent, not line-by-line paraphrase.
