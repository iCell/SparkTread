# 像素 2.5D 第一批生成提示词

日期：2026-09-03

生成方式：Codex 内置 imagegen；没有使用 CLI／API 回退。参考图仅用于视觉风格与尺度，未作为要修改的底图。

## 坦克四方向锚定图

```text
Use case: stylized-concept
Asset type: CURRENT production-direction game sprite reference sheet for a SpriteKit tank game.
Input images: Image 1 is a STYLE AND SHAPE-SCALE REFERENCE ONLY, not an edit target. Match its refined modern pixel-art craft, soft mechanical-toy personality, fixed elevated near-overhead 2.5D viewpoint, short downward screen-space side extrusion, compact tank proportions, palette and modest detail density. Create a new clean asset sheet, not a gameplay screenshot.

Primary request: Produce exactly TWELVE complete tank sprites in a precise 4-column by 3-row orthogonal sheet. Row 1 is one cyan-and-ivory PLAYER NORMAL tank in four cardinal facings: UP, RIGHT, DOWN, LEFT. Row 2 is one muted coral-red ENEMY NORMAL tank in the same order: UP, RIGHT, DOWN, LEFT. Row 3 is one muted coral-red ENEMY FIRE tank in the same order: UP, RIGHT, DOWN, LEFT. No labels or text.

Sprite designs:
- Player normal: humble starter tank; compact rounded blue-cyan hull, small ivory turret, exactly one simple straight ordinary barrel, two dark rubber tread strips. A tiny pale cyan stripe only. Not ornate, no energy reactor, no extra weapons.
- Enemy normal: clearly boxier muted coral/red hull, smaller plain round red turret, exactly one straight ordinary barrel and two dark tread strips. It must look truly common and low-threat, not like a boss.
- Enemy fire: same underlying enemy hull footprint but an unmistakable short wide ocher/coral flamethrower nozzle, plus exactly two compact cylindrical amber fuel-canister tops flanking the turret. No upward-facing chimney or mortar. The nozzle lies in the ground plane and points in the listed movement direction.
- Four directions are the same physical vehicle, not four redesigns. Preserve exact color placement, hull proportions, track width, turret design and accessory count in every direction. Do not mirror highlights: upper-left screen-space key light and the short visible front/down-screen side remain fixed consistently as the vehicle turns.
- All twelve hull footprints use exactly the same baseline size and ground contact center. Each sprite is small and compact, comparable to the tiny tanks in Image 1. Barrels may extend beyond the hull but may not touch cell borders.

Layout and technical presentation:
- A clean 4×3 grid on a genuinely transparent background. No checkerboard pattern and no colored backing.
- Equal square cells, generous identical padding. Each complete sprite centered on the same ground anchor in its cell. Nothing cropped, no overlaps, no missing tread/barrel, no black vertical artifacts.
- All twelve sprites at exactly the same scale. Tank art occupies roughly 45–50% of cell width including hull but excluding barrel, leaving ample extraction margin.
- Genuine hard-edged pixel clusters and stepped outlines at one consistent apparent pixel scale. About 3–4 shade clusters per material. Crisp nearest-neighbor look, restrained dark outlines, no antialiasing, subpixel blur, gradients, fine noise, paint texture, resampling halo or mixed pixel densities.
- A short soft pixel-cluster contact shadow may be included directly beneath/down-screen from each tank, identical footprint logic across directions; no long shadows.
- Pixel sprite sheet only: no frame, grid lines, dividers, captions, numbers, arrows, HUD, terrain, projectiles, muzzle flash, environment, phone frame, logos or watermark.

Composition/framing: wide 3:2 or 16:9 asset sheet, four perfectly aligned columns and three perfectly aligned rows. Every cell fully visible with generous outer margin.
Constraints: fixed 2.5D near-overhead view, not strict flat top-down, not diamond isometric, no perspective floor. Original vehicle designs, no national insignia, no copied game sprites, no eyes or faces.
```

## 方形基地四状态锚定图

```text
Use case: stylized-concept
Asset type: CURRENT production-direction square base state sprite reference sheet for a SpriteKit tank game.
Input images: Image 1 is a STYLE AND SCALE REFERENCE ONLY, not an edit target. Match its refined modern pixel-art craft, warm restrained palette, compact world-object scale, soft mechanical-toy personality and fixed elevated near-overhead 2.5D view with a very short down-screen front face.

Primary request: Produce exactly FOUR complete states of ONE original compact square Golden Eagle headquarters in a precise single horizontal row, in this order: HEALTHY, DAMAGED, CRITICAL, DESTROYED. No text or labels.

Base design invariants:
- Low, compact, unmistakably SQUARE ground footprint and square outer silhouette with only subtly chamfered corner pixels; width comparable to about 1.3 of the small tank hulls in Image 1.
- A flat ivory enamel square top plate in a restrained blue-gray metal frame. Centered on the top plate is one bold, simple, original amber-gold eagle silhouette/emblem readable at small scale. The emblem is decoration, not text; it must remain recognizable in healthy/damaged/critical states.
- Very short visible down-screen front wall in the fixed 2.5D view, with one small cyan status strip centered on the front. No dome, circular reactor, ring, octagonal footprint, tower, castle, giant platform, gun turret, national symbol or copied game sprite.
- States are the same exact structure, scale, footprint, anchor and screen-space lighting:
  1 HEALTHY: clean intact top plate, bright cyan status strip, clear gold eagle.
  2 DAMAGED: two small readable cracks, one chipped top corner, dim cyan strip, light soot; all silhouette edges mostly intact.
  3 CRITICAL: deeper cracks, two damaged/chipped edges, warm red/orange warning strip, restrained localized dark scorch and two tiny ember pixels; still unquestionably the same square base and fully standing.
  4 DESTROYED: collapsed square shell within the SAME footprint, broken ivory plate pieces, bent blue-gray frame, dark square crater/open center, a few tiny cool smoke pixel clusters; no active flame, no explosion, no debris outside extraction-safe margin.
- Damage progression changes condition, not camera, scale, palette family, footprint or identity.

Layout and technical presentation:
- A clean 4×1 grid on a genuinely transparent background. No checkerboard pattern and no colored backing.
- Equal square cells with generous identical padding. Every state centered on exactly the same ground anchor and baseline; matching visible extents except intentional compact collapse in destroyed. Nothing cropped or touching another cell; no grid lines, dividers, borders or cell background.
- Each base occupies roughly 50–55% of its cell width. All four use precisely one consistent apparent pixel density matching the tiny sprites in Image 1.
- Genuine crisp hard-edged pixel clusters, stepped contours, about 3–4 shade clusters per material, restrained dark outline and fixed upper-left screen-space lighting. No antialiasing, smooth gradient, blur, fine noise, resampling halo, painterly texture or mixed pixel scale.
- A short soft pixel-cluster contact shadow directly beneath/down-screen may appear, same anchor in all states.
- No defensive bricks around it: this sheet contains ONLY the base object states. No tanks, terrain, HUD, weapons, arrows, captions, numbers, logos or watermark.

Composition/framing: wide horizontal asset sheet, four perfectly aligned equal cells, generous outer margin.
Constraints: fixed 2.5D near-overhead pixel view, not strict flat top-down and not diamond isometric; complete square silhouettes visible.
```

## 透明提取记录

对坦克图调用内置 imagegen 进行一次仅背景提取的编辑，但结果仍为 RGB、没有 Alpha，未选入当前目录。没有对基地重复已确认无效的步骤，也没有用滤镜、脚本或手工抠图伪造运行时交付。

