# ADR-0020: Owner Rules — AP Cuts Brick Two Cells Deep; Distinct White Brick and White Steel Colours (GAME_RULES R5.4–R5.5)

Status: Accepted (owner instruction of 2026-09-15 after a device run: "现在的白墙应该是乳白色的那种，精钢应该是偏白色；另外，穿甲弹打到红砖的效果提升一倍"; asked whether white brick doubles too, the owner answered "要")  
Date: 2026-09-15  
Related findings / supersessions: amends ADR-0018 (GAME_RULES §3.1, §3.3, §3.4, §14.3)

## Context

R5 gave the AP round a 2-cell-wide, 1-cell-deep strip on every breakable wall. On the device the owner wanted AP to be twice as effective against red brick. The same run showed the white tiers wrong: SpriteKit's `colorBlendFactor` multiplies a tint into the texture, so the near-white tints left white brick looking red and white steel looking like grey steel.

## Decision

1. The AP strip is 2 cells deep (4 quadrant rows) in columns whose first standing material is red or white brick, and stays 1 cell deep for grey steel. White brick still takes two rounds per quadrant, so two AP rounds open two cells of it — white brick keeps twice red brick's durability. Width (2 cells) and the stop-after-contact rule are unchanged. Each column's depth follows its first material; empty quadrants in front of it spend depth. Data: `WeaponDefinition.brickStripDepthQuadrants` (optional; nil means the general depth). The field was first red-brick-only; widening it bumped the replay format to 9.
2. White brick renders as a pale stone brick (face ≈ 188,184,174, cracked ≈ 156,150,140, relief ×1.35, dark joints) and white steel as polished silver plate (face ≈ 222,230,238, relief ×1.7, near-black joints) — each a harder-looking version of its base material. Two earlier passes (milky ivory against near-white, then ivory against pale silver-blue) looked soft and alike on the device; the owner asked for colours that read harder than red brick and steel. The four walls now differ in hue, brightness and contrast at once: orange-red brick, light grey stone, blue-grey steel, bright silver. The adapter recolours the brick/steel atlas textures on the CPU by luminance, keeping the bevels, mortar and plate joints, and caches the results.
3. Also fixed on the same run: the arena now reads the safe-area insets from its SKView, since the SwiftUI proxy that ignores the safe area reported zero and the arena ran under the Dynamic Island (GAME_RULES §15.1).

## Alternatives considered

- Doubling the width instead of the depth: rejected, a 4-cell notch is wider than a tank and changes the corridor geometry the strip rules were built on.
- Doubling AP against red brick only: the first step, reversed when the owner confirmed white brick doubles too, which keeps the 2× durability relation.
- A per-node SKShader for the white tiers: rejected, CPU recolouring of 16×16 textures is simpler and matches the pixel pipeline.

## Gameplay consequences

AP opens a 2-cell-thick red brick wall with one round and a 2-cell-thick white brick wall with two. White brick and white steel are now visually distinct from red brick and grey steel.

## Architecture consequences

GameCore strip resolution picks depth per column by material; AppleAdapters gains a recolour cache and reads SKView safe-area insets.

## Migration cost

Replay format 9: format-8 recordings and suspended sessions are refused as incompatible.

## Tests affected

R5 wall-strip suites (AP brick depth for red and white brick, steel unchanged, depth from the first material); replay format boundary.
