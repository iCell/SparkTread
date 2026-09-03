# 本轮生成提示词

内置 imagegen；用户已确认本地后处理。纯色底用于确定性提取，不是伪透明。来源图片经检查后再导出透明成品。以下尺寸、网格是生成目标，实际以元数据与检查为准。

## hulls

```text
Use case: stylized-concept
Asset type: modular game sprite sheet, CHASSIS ONLY.
Image 1: reference for exact refined pixel-art style, compact mechanical toy tank proportions, fixed elevated 2.5D view, palette and lighting. It is not an edit target.
Create 20 chassis sprites, FOUR COLUMNS and FIVE ROWS, regular equal square cells, no labels. Columns are UP, RIGHT, DOWN, LEFT facings. Every direction is a view of the same chassis, not the same front view with a rotated gun. Row1 cyan player hull, Row2 slim red scout hull, Row3 plain red standard hull, Row4 red armored hull with substantial corner armor, Row5 dark red heavy hull with wider heavy track guards. All ground footprints fit the same square size; increasingly heavy silhouettes change structure not merely color.
IMPORTANT: NO TURRETS, NO GUNS, NO CANNONS, NO WEAPONS. Every chassis has a simple flat center mounting plate, leaving plenty of empty flat deck area for separately composited turrets. Show two complete black/rubber tread assemblies for each direction. Track direction follows movement facing. Modest pixel stepping, 3–4 shades per material, consistent apparent pixel size, screen-space lighting from upper left, very shallow vertical thickness. Crisp, clean, low detail density; not 3D renders, not blurred. Keep complete silhouettes and contact edges, no ground shadow.
Regular 4x5 equal-cell grid, generous empty space at cell edges, ground contact centers precisely aligned within each cell, body occupies 50–55% cell width. Consistent scale, no clipped edges, no extra parts or objects.
Background is ONE FLAT SOLID PURE MAGENTA (#FF00FF), for deterministic local chroma-key extraction. No transparency checkerboard, no white backdrop, no labels/text/grid/border/watermark. Foreground never uses this magenta. Original design.
```

## turrets_a

```text
Use case: stylized-concept
Asset type: modular TURRETS ONLY sprite sheet for the referenced pixel-art tanks.
Image 1 is the exact visual style reference, not an edit target. Refined compact mechanical-toy pixel art, 2.5D fixed elevated near-overhead view, shallow down-screen side faces, upper-left lighting fixed in screen space.
Create exactly SIXTEEN detached turret modules in a regular 4-column x 4-row grid. Columns are facing UP, RIGHT, DOWN, LEFT. Rows:
1. Plain ivory/cyan PLAYER NORMAL turret with one simple straight barrel.
2. Plain coral-red ENEMY NORMAL turret with one simple straight barrel.
3. RAPID turret: muted olive-green compact turret with TWO distinct parallel thin forward barrels and two compact feed drums. Obvious twin-barrel silhouette.
4. FIRE turret: coral/ochre short wide nozzle, compact red central turret and TWO small amber fuel canisters flanking it. Obvious fuel-canister silhouette. No flame or muzzle flash.
Only turret and attached weapon hardware, NO hull, treads, chassis, shadow, floor or tank body. Turret mounting pivot is at center of each identical cell. One physical design per row viewed four ways; keep shapes/colors fixed, only direction changes. Barrels lie horizontally in the map plane, no vertical mortar chimney. All four directions use same scale.
Hard square pixel clusters, 3–4 shades/material, softened stepped mechanical silhouettes, selective dark outlines, no gradients or blur, modest detail. Equal padding, complete barrels, no clipped pixels.
ONE FLAT SOLID PURE MAGENTA (#FF00FF) extraction background, no checkerboard, no labels/grid/frame/text/watermark. Foreground never uses pure magenta. Original designs.
```

## turrets_b

```text
Use case: stylized-concept. Asset type: TURRETS ONLY pixel game sprite sheet.
Image1 style reference only. Match compact soft mechanical-toy pixels, fixed elevated near-overhead 2.5D view, short down-screen side, upper-left light in screen coordinates.
TWELVE separate turret modules, FOUR columns x THREE rows. Columns UP, RIGHT, DOWN, LEFT. Rows:
1 AP: small violet turret, ONE long slender steel needle barrel and compact rectangular recoil collar. Elegant thin penetrating weapon, not a laser orb.
2 Explosion: amber/orange reinforced squat turret, ONE short extremely wide cannon with two barrel bands. Heavy chunky but compact, not a vertical mortar.
3 Mine: bronze low squared deployment deck, TWO visible flat circular mine discs on the rear side, a small simple gray forward normal-fire barrel. Mine dispenser at REAR, forward barrel at FRONT. Discs move consistently to opposite side of facing across four views.
NO hulls, treads, body, shadow, explosions, flame, projectiles. Mounting center identically aligned in each equal cell. Four views of same design/scale. All barrels flat along map plane; neither upward chimney nor isometric diagonal. Smoothly stepped mechanical silhouettes made from hard square pixel clusters; three/four shades per material, clear weapon silhouettes, no blur, gradient, antialiasing, noise or 3D rendering.
ONE FLAT PURE MAGENTA #FF00FF background, generous equal padding, no clipping, no grid, labels, numbers, text, logos or watermarks. Foreground never uses pure magenta.
```

## terrain

```text
Use case: stylized-concept. Asset type: reusable PIXEL ART game terrain module sheet. Image1 is the approved style reference only: warm sand, terracotta low bricks, gray-blue steel, teal water, sage bushes; fixed elevated 2.5D view, shallow vertical faces, axis-aligned square ground plane, not diamond isometric.
Create exactly SIXTEEN modules in a clean regular FOUR by FOUR equal-cell grid, no labels. Row-major order:
Row1: (1) square warm ocher/sand floor texture with quiet sparse pixel grain, (2) square muted mossy-earth floor texture, (3) square cool gray industrial floor texture, (4) square pale blue ice surface texture with very sparse cracks.
Row2: (5) short low terracotta brick wall module, two staggered courses, square ground footprint and short down-screen front face, (6) square gray-blue steel wall cap with shallow front face, (7) compact boundary wall module half brick half gray-blue cap, (8) small square wood-and-metal bridge-deck module.
Row3: (9) compact sparse sage shrub patch, (10) denser rounded sage shrub patch, (11) small group of warm stones, (12) small charred brick rubble patch.
Row4: (13) square quiet teal water surface with three short pixel ripples and NO shore/embankment, (14) small lily-pad cluster, (15) square metal drain grate inset into flat ground, (16) square flat cyan-ring spawn platform inset into ground.
All 16 modules use one consistent style and pixel density, around 32–48 meaningful logical pixels across each art block. Readable when small, 3–4 shades/material, crisp square pixel clusters, no smooth gradients, noise overlay or antialiasing. First four floor squares and water surface are OPAQUE tile textures with sharp axis-aligned square edges and no thickness/shadow; they have only a magenta margin. Other props have isolated complete silhouettes with no ground-painted halo.
Each module occupies 55–65% of a cell, equal scale, generous padding, never overlapping. Single FLAT PURE MAGENTA #FF00FF background for local extraction, no checkerboard, no text, no gridlines, no HUD, tanks, base, labels, frame or watermark.
```

## equipment

```text
Use case: stylized-concept. Asset type: modular equipment ATTACHMENTS ONLY pixel game sheet.
Image1 is a style reference: refined soft mechanical-toy pixels, compact 2.5D elevated view, fixed upper-left screen light.
SIXTEEN detached equipment groups in FOUR columns x FOUR rows. Columns face UP RIGHT DOWN LEFT. Rows:
1 Amphi: a symmetric PAIR of small ivory/cyan flotation pontoons with tiny rear waterjet hardware, no water. Pair placed outside imaginary tank tread edges, empty center.
2 AntiSkid: a PAIR of dark-gray segmented ice-grip track-shoe strips with small steel studs, no chassis; empty center.
3 Moon shield: one compact blue-gray crescent-shaped projector attached to a slim side arm, luminous pale cyan crescent sliver. No surrounding big bubble.
4 Memory of Sea: tiny ivory mechanical memory capsule with four colored tabs (cyan, amber, coral, violet) and a simple small round central lens; no huge aura.
Identical center anchors and scale per row across all four directions, keep 2.5D side shading fixed as orientation changes, equipment compact relative to a small tank; no tanks, turrets, hulls, treads beyond row2 shoe strips, ground, shadows, UI or scenery.
One consistent pixel density, crisp hard square pixels, 3 shades per material, no blur/gradients/noise. All complete with generous cell margins.
Single flat PURE MAGENTA #FF00FF background for extraction, no checkerboard, text, labels, grid, border, logos or watermark.
```

## pickups

```text
Use case: stylized-concept. Asset type: pixel-art GAME PICKUP ICON sprite sheet.
Image1 is STYLE reference only, not an edit. Match refined compact soft mechanical-toy pixels and friendly readable silhouettes.
Create exactly TWENTY-FIVE separate icons on a regular FIVE by FIVE equal-cell grid. Row-major order:
Row1: speed lightning bolt; armor shield; firepower single cartridge; level-up double chevrons; maximum speed/firepower lightning-and-cartridge pair.
Row2: small ivory/cyan twin flotation pontoons; dark studded ice-grip track shoes; pale cyan crescent shield; small four-colored memory capsule; bronze score star medal.
Row3: silver score star medal; gold score star medal; platinum score star medal; cyan invincibility bubble with star; square golden-eagle base with a cyan protective arch.
Row4: pale blue snowflake freeze; round black/orange bomb; red heart extra life; armor shield with cartridge pair; small wooden ammo crate with brass cartridges.
Row5: olive twin-barrel Rapid weapon; compact orange flame; violet long AP cartridge; chunky amber explosive shell; flat bronze mine disc with orange tabs.
No text, numbers or badge lettering. Each icon a standalone symbol with a strong unique shape, not a square button or colored tile, no outer common frame. Icons around 50–60% cell width, equal optical weight. All complete, equal padding, no clipping. Pure deliberate pixel clusters, 3–4 shade ramps, crisp stepped silhouettes and simple detail that remains legible at 20–24 px. No smooth gradients, blur, soft 3D render, fine grain or mixed pixel size.
Background ONE FLAT PURE MAGENTA #FF00FF for extraction. No checkerboard/grid/divider/captions/logo/watermark. Foreground never pure magenta.
```

## projectiles

```text
Use case: stylized-concept. Asset type: pixel-game projectile and mine sprite sheet. Image1 style reference only. Compact friendly mechanical-toy pixels, restrained bright combat accents, crisp square clusters.
Exactly TWENTY individual items in FIVE columns x FOUR rows, equal cells, no labels.
Row1, nose points UP for all: small warm gold normal capsule bullet; very slender lime rapid needle bullet; small orange/cream teardrop fire projectile; long thin violet-white AP needle; short chunky amber explosive shell.
Row2: five separate short trailing effects corresponding to the Row1 weapons: gold dashes; lime speed dashes; orange flame tail; violet fine streak; amber smoke/ember tail. Oriented vertically, travel upward, no bullet body.
Row3: FOUR armed mine levels then one small metal debris cluster. Levels0–3: (1) plain bronze round disc with tiny orange status light; (2) disc with two orange tabs; (3) reinforced disc with four chunky orange tabs; (4) heavy hexagonal mine with six distinct orange spokes. Compact consistent footprint and same center, view slightly elevated 2.5D, low profile not tall.
Row4: same FOUR mines in same order but dormant: lights dim/dark, mechanisms unchanged; then one small terracotta brick debris cluster.
Clean isolated sprites with generous margins, no ground or shadow, nothing cropped. No explosions. All materials 3–4 pixel shade clusters, no blur, glow halo, gradients, smooth 3D render or noise. Pure flat MAGENTA #FF00FF background for deterministic extraction, no checkerboard, grid, labels, text or watermark. Foreground never pure magenta.
```

## effects

```text
Use case: stylized-concept. Asset type: pixel-game VFX sprite animation sheet. Image1 style reference only, matching refined compact mechanical-toy pixel style.
Exactly TWENTY-FOUR standalone effects, FOUR columns x SIX rows, regular equal square cells. Each row shows four successive animation poses left to right, all with the SAME center anchor, no labels.
Row1: gold/cream ordinary muzzle flash pointing UP, small ignition > compact star peak > sparse sparks > faint last ember.
Row2: orange/cream fire burst pointing UP, ignition > full compact flame > curled flame > embers.
Row3: compact tank explosion, white/amber kernel > orange lobed blast > dark orange hollow blast > sparse ember ring.
Row4: gray-brown smoke puff, tiny > medium > open dissipating cloud > tiny separated remnants.
Row5: blue/ivory water splash, first droplets > upward splash > spreading short ring > sparse ripples.
Row6: metal-hit spark burst, tiny gold first contact > several radial white/gold sparks > thinner sparks > two faint remnant pixels.
Keep very readable hard pixel clusters, 3–4 shade ramps, no antialiased edges, gradient glow, soft haze, painting or 3D. Animation has changes of shape, not just size/fade copies. No giant scene-filling blasts. Entire effects in each cell with generous margins, no cut debris. No attached guns, bullets, tanks, terrain or HUD.
ONE FLAT SOLID PURE MAGENTA #FF00FF background for extraction, not transparent checkerboard, no text/grid/captions/frames/logos/watermark.
```
# Environment finish sheet

Built-in imagegen; source `environment.png`. Uses the approved arena only as a style reference. Ordered 4×4: single chunky clay/steel blocks, clay/steel debris; moss, pebbles, earth cracks, small flowers; water/ice material squares, north-south/east-west bridges; outer corner/straight border, straight/corner bank. Fixed elevated screen-aligned view, shallow front faces, upper-left light, refined stepped pixel clusters, wide solid magenta gutters for the user-approved local extraction. No tanks, labels, UI, or complete map. Runtime map previews are rendered separately by SpriteKit.
# Full environment prompt

Use case: stylized-concept. Asset type: production environment sprite sheet for SpriteKit fixed-view 2.5D pixel tank arcade. Image 1 is STYLE REFERENCE ONLY, do not reproduce the full map.
Create one precisely ordered 4 column x 4 row sheet of SIXTEEN separate props/material samples with wide perfectly flat magenta #FF00FF gutters/background for deterministic key extraction. Each subject centered in its own equally spaced cell. NO text, frames, grids, labels, numbers, logo, UI, tank, or entire map. CRISP refined low-resolution pixel art with clear stepped clusters, warm clay, subdued teal, golden sand, moss olive. Match the reference's short shallow front faces, soft chunky beveled edges, attractive hand-pixeled tactile feel. Fixed elevated near-top-down view, screen-aligned square footprint, NOT isometric diamonds or perspective convergence. Lighting upper left throughout.
Rows read left to right:
row1: ONE single warm ochre clay wall block with large square top and a short dark front face (not a wall of small bricks); ONE single cool blue-gray steel wall block same footprint, bevel and short front face; tiny clay block rubble with 4-5 stones; tiny steel block rubble with 3-4 shards.
row2: sparse flat olive grass/moss patch with irregular tiny satellite leaves; tiny low-profile sand pebble scatter; shallow sandy cracked-earth decal, irregular edges; small scrub/flower patch olive leaves with just 2 tiny cream blossoms.
row3: square deep teal pond-water material sample without bank, subtle irregular pale ripples and gently variegated depth color; square frosted ice material sample with subtle cracks; narrow wooden bridge pointing north/south, a short low bridge deck supported by two short side rails; SAME bridge pointing east/west with consistent lighting.
row4: low L-shaped outer clay border corner with one steel corner post; low straight clay border segment 3 blocks long with moss at base; short horizontal tan earthen pond bank with light top rim, dark recessed soil edge, tiny pebbles, water immediately below edge; curved right-angle matching pond-bank corner with water inside.
No big diffuse shadow. Details should survive downsampling to 24-40px. All sixteen complete silhouettes fully inside cells, none cropped or touching. Background solid magenta, no magenta in objects.
# Base background cleanup prompt

Use case: background-extraction. Image 1 is the EDIT TARGET. These are four approved game base damage states, left to right healthy, damaged, critical, destroyed. Keep the four square bases, their ivory faces, gold eagle emblem, blue-gray metal frame, cracks, little status light, and fixed near-top-down shallow 2.5D pixel shading unchanged in design. Keep the four equally spaced subjects the same size on a one-row sheet. Change ONLY the exterior background and baked exterior contact-shadow fringe: replace every checkerboard/white/gray backdrop pixel outside each subject, including the old gray drop shadow, with perfectly solid pure magenta #FF00FF. No new white outline, no shadow on magenta, no white fringe. Crisp hard silhouette separation. Do not remove ivory inside the bases. Preserve metal outer corners and destroyed rubble. No text, grid, extra objects, perspective changes, or full scene. This solid key-color sheet will be locally extracted into alpha by an explicitly user-approved workflow.

