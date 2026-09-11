import SpriteKit
import GameApplication
import GameCore

/// VS-01 / Combat Lab renderer: draws the world with PixelProduction art and
/// mirrors the authoritative state each frame. Render-only — the simulation
/// is advanced exclusively by the display-link driver (ADR-0007); this scene
/// never steps, pauses, or gates ticks. Everything transient (impacts,
/// pickups, shield transitions) is driven by domain-event payloads, never by
/// re-querying entities that may already be gone.
final class MovementLabScene: SKScene {
    private let controller: MovementLabController
    /// Retained across stage restarts and surface changes: the manifest and
    /// atlases decode once; a failed load is retried on the next rebuild.
    private var art: PixelArt?
    /// The loaded art, for presentation that lives outside the scene (the
    /// results-table icons); nil until the scene has built once.
    var loadedArt: PixelArt? { art }
    private var debugLabel: SKLabelNode?
    /// Intro curtain: one opaque tile per cell, lifted in cross-shaped
    /// strips from the arena centre as `StageFlow.revealStep` grows
    /// (reference reveal, ADR-0011). Empty for worlds that open in play.
    private var curtainTiles: [(cell: Vec2i, node: SKSpriteNode)] = []
    private var curtainStep: Int?? = .some(nil)
    /// Outro cover: the same tiles, dropped from the arena edges toward the
    /// centre as `StageFlow.coverStep` grows (a closing box iris).
    private var coverTiles: [(cell: Vec2i, node: SKSpriteNode)] = []
    private var coverStep: Int?? = .some(nil)
    private var collisionBox: SKShapeNode?
    /// Liquid tiles keyed by cell index; re-tiled every frame from the
    /// live terrain so melting ice heals edges automatically.
    private var liquidNodes: [Int: (node: SKSpriteNode, kind: String)] = [:]
    /// Foliage overlay per cell (plan §7.3 "occludes tanks/projectiles
    /// visually"; ADR-0016): above tanks, below mines and projectiles so
    /// ordnance stays readable (§12.3); cells over the player's footprint
    /// fade so the player stays readable (vendor guidance).
    private var foliageNodes: [Int: SKSpriteNode] = [:]
    static let foliageZPosition: CGFloat = 520
    /// Foliage over the player: thin enough to keep one's own tank readable.
    static let foliageFadedAlpha: CGFloat = 0.45
    /// Foliage over any other tank. Owner rule (2026-09-11): a tank in the
    /// bushes stays visible, it is only hard to make out — so cover never
    /// hides a tank outright, it just thins over one.
    static let foliageOverTankAlpha: CGFloat = 0.72
    private var layout: ArenaLayout?

    // Dynamic mirrors keyed by entity ID.
    private var tankNodes: [Int: PixelTankNode] = [:]
    private var tankFacings: [Int: Direction] = [:]
    private var tankTravel: [Int: Int] = [:]
    private var tankPositions: [Int: Vec2i] = [:]
    private var tankEquipment: [Int: String?] = [:]
    private var projectileNodes: [Int: SKSpriteNode] = [:]
    private var mineNodes: [Int: (node: PixelMineNode, surface: PixelMineSurface, firstSeen: Int)] = [:]
    private var hazardNodes: [Int: SKSpriteNode] = [:]
    private var wallNodes: [Int: SKSpriteNode] = [:]
    private var pickupNodes: [Int: (node: PixelPickupNode, firstSeen: Int)] = [:]
    private var telegraphNodes: [Int: SKSpriteNode] = [:]
    private var baseNode: PixelBaseNode?
    /// Adapter-owned tinted silhouette for base-hit flashes (the vendor
    /// base node's sprites are private; an SKAction on the plain node would
    /// not tint them).
    private(set) var baseFlash: SKSpriteNode?
    /// Transient effects age on the PRESENTATION clock (`presentationTime`,
    /// accumulated from frame deltas, so it pauses with the view and runs on
    /// through a cutscene), never on the world tick: the decisive tick's
    /// explosion must play out while the outro holds the world (R11-01).
    private var transientEffects: [(node: PixelEffectNode, born: TimeInterval)] = []
    private var presentationTime: TimeInterval = 0
    /// The controller activity generation the clock last saw; a change means
    /// a suspension happened since the previous frame, so the clock rebases.
    private var seenActivityGeneration: Int?
    private var scorchNodes: [SKSpriteNode] = []
    private var builtGeneration = -1
    private var audio: GameAudio { controller.audio }
    private var haptics: GameHaptics { controller.haptics }
    /// Presentation clock for frame-rate-independent smoothing.
    private var lastUpdateTime: TimeInterval?
    /// Base shield presentation edge: set on an observed inactive→active
    /// transition only (a rebuild with the shield already up shows `.active`).
    private var shieldActivatedTick: Int?
    private var wasShielded = false

    private var cellPoints: CGFloat = 0
    private var artScale: CGFloat = 0

    /// Bounded pools (delivery §5: "external must provide bounded pools").
    private static let maxTransientEffects = 48
    private static let maxScorchDecals = 24

    init(size: CGSize, controller: MovementLabController) {
        self.controller = controller
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic scene") }

    override func didMove(to view: SKView) {
        rebuildWorldView()
    }

    /// The hosting surface changed (multitasking, rotation): re-lay-out on
    /// the same scene and world — no authority reset, no event replay, no
    /// asset reload.
    func surfaceDidChange(to newSize: CGSize) {
        guard newSize != .zero, newSize != size else { return }
        size = newSize
        rebuildWorldView()
    }

    private func rebuildWorldView() {
        builtGeneration = controller.worldGeneration
        removeAllChildren()
        liquidNodes.removeAll(); tankNodes.removeAll(); projectileNodes.removeAll()
        mineNodes.removeAll(); hazardNodes.removeAll(); wallNodes.removeAll()
        pickupNodes.removeAll(); telegraphNodes.removeAll()
        tankFacings.removeAll(); tankTravel.removeAll(); tankPositions.removeAll()
        tankEquipment.removeAll()
        transientEffects.removeAll(); scorchNodes.removeAll(); burnedGrassNodes.removeAll(); baseNode = nil; baseFlash = nil
        debugLabel = nil; collisionBox = nil
        curtainTiles.removeAll(); curtainStep = .some(nil)
        coverTiles.removeAll(); coverStep = .some(nil)
        foliageNodes.removeAll()
        let world = controller.session.world
        wasShielded = (world.base?.shieldRemainingTicks ?? 0) > 0
        shieldActivatedTick = nil
        let layout = ArenaLayout(surface: size, arena: world.arena)
        self.layout = layout
        cellPoints = layout.cellPoints
        artScale = cellPoints / 16
        do {
            if art == nil { art = try PixelArt() }
            guard let art else { return }
            try buildTerrain(art, world: world)
            if controller.flow.isIntro { buildCurtain(layout: layout, world: world) }
            if controller.isLab { buildDebugOverlay() }
        } catch {
            art = nil // retry on the next rebuild; never sync against a half-built scene
            let n = SKLabelNode(fontNamed: "Menlo-Bold")
            n.text = "asset load failed: \(error)"
            n.fontSize = 14; n.fontColor = .red
            n.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(n)
        }
    }

    /// Test seam: installs the art and layout without a view or bundle, then
    /// runs the per-frame mirrors once so nodes exist for assertions.
    func installForTests(art: PixelArt, world: WorldState) {
        self.art = art
        let layout = ArenaLayout(surface: size, arena: world.arena)
        self.layout = layout
        cellPoints = layout.cellPoints
        artScale = cellPoints / 16
        syncForTests(world: world)
    }

    func syncForTests(world: WorldState) {
        guard let art else { return }
        syncTanks(art, world: world)
        syncBase(art, world: world)
        animateLiquids(art, world: world)
        animateFoliage(art, world: world)
    }

    /// Test seam: one presentation frame of `elapsed` seconds — drains the
    /// controller's events into effects and ages the live ones.
    func advanceForTests(world: WorldState, elapsed: TimeInterval) {
        guard let art else { return }
        presentationTime += elapsed
        processEvents(art, world: world)
    }

    var transientEffectCountForTests: Int { transientEffects.count }
    var presentationTimeForTests: TimeInterval { presentationTime }

    private func scenePoint(_ p: Vec2i) -> CGPoint { layout?.scenePoint(p) ?? .zero }

    private func centerPoint(_ topLeft: Vec2i, size sizeSubunits: Int) -> CGPoint {
        scenePoint(Vec2i(x: topLeft.x + sizeSubunits / 2, y: topLeft.y + sizeSubunits / 2))
    }

    // MARK: - Static terrain

    private func buildTerrain(_ art: PixelArt, world: WorldState) throws {
        let arena = world.arena
        // 3×3-cell ground tiles; the last column/row is clipped to the
        // arena (UV rect AND displayed size), never spilled into the gutter.
        for y in stride(from: 0, to: arena.cellsHigh, by: 3) {
            for x in stride(from: 0, to: arena.cellsWide, by: 3) {
                let spanX = min(3, arena.cellsWide - x), spanY = min(3, arena.cellsHigh - y)
                let id = "px_ground_frontier_\((x / 3 + y / 3) % 9)"
                let full = try art.texture(id)
                let texture = spanX == 3 && spanY == 3 ? full
                    : SKTexture(rect: CGRect(x: 0, y: 1 - CGFloat(spanY) / 3,
                                             width: CGFloat(spanX) / 3, height: CGFloat(spanY) / 3),
                                in: full)
                texture.filteringMode = .nearest
                let n = SKSpriteNode(texture: texture)
                n.size = CGSize(width: cellPoints * CGFloat(spanX), height: cellPoints * CGFloat(spanY))
                n.position = CGPoint(
                    x: cellCenter(x: x, y: y).x + cellPoints * CGFloat(spanX - 1) / 2,
                    y: cellCenter(x: x, y: y).y - cellPoints * CGFloat(spanY - 1) / 2)
                n.zPosition = 0
                addChild(n)
            }
        }
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                reconcileTerrainCell(art, world: world, cellX: x, cellY: y)
            }
        }
    }

    /// Brings one cell's static nodes in line with the authoritative terrain
    /// in both directions: walls appear/disappear/re-texture, liquids appear
    /// (a restored water cell) or disappear (hardened, melted). Neighbour
    /// joints are refreshed by the callers / per-frame liquid pass.
    func reconcileTerrainCell(_ art: PixelArt, world: WorldState, cellX: Int, cellY: Int) {
        refreshWallTexture(art, world: world, cellX: cellX, cellY: cellY)
        let key = cellY * world.arena.cellsWide + cellX
        let kind = world.terrain[cellX, cellY].kind
        if kind == .water || kind == .ice {
            let name = kind == .water ? "water" : "ice"
            if let existing = liquidNodes[key], existing.kind != name {
                existing.node.removeFromParent()
                liquidNodes[key] = nil
            }
            if liquidNodes[key] == nil,
               let n = try? art.sprite(String(format: "px_%@_000_0", name), scale: artScale) {
                n.position = cellCenter(x: cellX, y: cellY)
                n.zPosition = 5
                addChild(n)
                liquidNodes[key] = (n, name)
            }
        } else if let existing = liquidNodes.removeValue(forKey: key) {
            existing.node.removeFromParent()
        }
        if kind == .foliage {
            if foliageNodes[key] == nil, let n = try? art.sprite("px_foliage_000_0", scale: artScale) {
                n.position = cellCenter(x: cellX, y: cellY)
                n.zPosition = Self.foliageZPosition
                addChild(n)
                foliageNodes[key] = n
            }
        } else if let existing = foliageNodes.removeValue(forKey: key) {
            existing.removeFromParent()
        }
    }

    /// Per-frame foliage pass: the 8-neighbour joint mask and a slow frame
    /// cycle, and the local fade over any tank standing in the cover.
    private func animateFoliage(_ art: PixelArt, world: WorldState) {
        guard !foliageNodes.isEmpty else { return }
        let frame = (world.tick / 20) % 3
        let width = world.arena.cellsWide
        let cell = SpatialUnits.subunitsPerCell, footprint = SpatialUnits.standardTankFootprintSubunits
        // The mirrored world's own player (not the controller's): the scene
        // draws what it is handed, as every other mirror here does.
        let player = world.player(.one)?.tankEntityID.flatMap { world.tank(entityID: $0) }
        for (key, node) in foliageNodes {
            let cx = key % width, cy = key / width
            guard world.terrain.isInside(cellX: cx, cellY: cy), world.terrain[cx, cy].kind == .foliage else {
                node.removeFromParent()
                foliageNodes[key] = nil
                continue
            }
            var mask = 0
            let offsets = [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0),
                           (16, 1, -1), (32, 1, 1), (64, -1, 1), (128, -1, -1)]
            for (bit, dx, dy) in offsets
            where world.terrain.isInside(cellX: cx + dx, cellY: cy + dy)
                && world.terrain[cx + dx, cy + dy].kind == .foliage { mask |= bit }
            for (diag, a, b) in [(16, 1, 2), (32, 2, 4), (64, 4, 8), (128, 8, 1)]
            where mask & a == 0 || mask & b == 0 { mask &= ~diag }
            if let texture = try? art.texture(String(format: "px_foliage_%03d_%d", mask, frame)) {
                node.texture = texture
            }
            func covers(_ position: Vec2i) -> Bool {
                cx * cell < position.x + footprint && (cx + 1) * cell > position.x
                    && cy * cell < position.y + footprint && (cy + 1) * cell > position.y
            }
            if let player, covers(player.positionSubunits) {
                node.alpha = Self.foliageFadedAlpha
            } else if world.tanks.contains(where: { covers($0.positionSubunits) }) {
                node.alpha = Self.foliageOverTankAlpha
            } else {
                node.alpha = 1
            }
        }
    }

    /// Test seam: the foliage node of a cell and its alpha.
    func foliageNodeForTests(cellX: Int, cellY: Int, world: WorldState) -> SKSpriteNode? {
        foliageNodes[cellY * world.arena.cellsWide + cellX]
    }

    func refreshWallTexture(_ art: PixelArt, world: WorldState, cellX: Int, cellY: Int) {
        let key = cellY * world.arena.cellsWide + cellX
        let cell = world.terrain[cellX, cellY]
        guard cell.kind.isWall, cell.quadrantMask != 0 else {
            wallNodes.removeValue(forKey: key)?.removeFromParent()
            return
        }
        let node: SKSpriteNode
        if let existing = wallNodes[key] {
            node = existing
        } else {
            // Shield pickups/expiry rebuild previously destroyed fort cells.
            node = SKSpriteNode()
            node.size = CGSize(width: cellPoints, height: cellPoints)
            node.position = cellCenter(x: cellX, y: cellY)
            node.zPosition = 100
            addChild(node)
            wallNodes[key] = node
        }
        // The reference draws all four materials with two patterns and
        // different palettes (GAME_RULES §3.5), so the white tiers reuse the
        // brick/steel atlases with a tint; cracked white brick darkens.
        let name = cell.kind.isBrickFamily ? "brick" : "steel"
        switch cell.kind {
        case .whiteBrick, .whiteSteel:
            node.color = .white
            node.colorBlendFactor = cell.crackMask != 0 ? 0.45 : 0.62
        default:
            node.colorBlendFactor = 0
        }
        var mask = 0
        for (bit, dx, dy) in [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0)]
        where world.terrain.isInside(cellX: cellX + dx, cellY: cellY + dy)
            && world.terrain[cellX + dx, cellY + dy].kind == cell.kind { mask |= bit }
        // Atlas remaining-mask ids use the delivery's quadrant numbering;
        // full cells use 15, damaged cells their mask. Keep the old texture
        // if a specific damage combination is missing from the atlas.
        if let texture = try? art.texture(String(format: "px_%@_joint_%02d_%02d", name, mask, cell.quadrantMask)) {
            node.texture = texture
        }
    }

    private func cellCenter(x: Int, y: Int, span: Int = 1) -> CGPoint {
        scenePoint(Vec2i(x: x * SpatialUnits.subunitsPerCell + span * SpatialUnits.subunitsPerCell / 2,
                         y: y * SpatialUnits.subunitsPerCell + span * SpatialUnits.subunitsPerCell / 2))
    }

    private func buildDebugOverlay() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 10
        label.fontColor = SKColor(white: 1, alpha: 0.8)
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: (layout?.origin.x ?? 0) + 8, y: size.height - 16)
        label.zPosition = 9000
        addChild(label)
        debugLabel = label

        let box = SKShapeNode()
        box.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.9)
        box.lineWidth = 1
        box.zPosition = 900
        addChild(box)
        collisionBox = box
    }

    // MARK: - Per-frame mirror

    override func update(_ currentTime: TimeInterval) {
        if builtGeneration != controller.worldGeneration {
            rebuildWorldView() // stage restart rebuilt the world
        }
        // The presentation clock follows the CONTROLLER's activity (R12-01),
        // not the render loop: a frame delivered while suspended ages
        // nothing, and the first frame after a resumption starts from zero
        // elapsed, so suspended time is never counted — whether or not the
        // host kept rendering. (The view also pauses the SCENE while the
        // scene phase is inactive, which parks SKActions too — never the
        // SpriteView through `isPaused:`, which blanked the SKView.)
        guard controller.isRunning else {
            lastUpdateTime = nil
            return
        }
        if seenActivityGeneration != controller.activityGeneration {
            // A start (possibly after a suspension that produced no frame at
            // all): this frame is the new zero, whatever the timestamp gap.
            seenActivityGeneration = controller.activityGeneration
            lastUpdateTime = nil
        }
        let elapsed = min(0.1, max(0, currentTime - (lastUpdateTime ?? currentTime)))
        lastUpdateTime = currentTime
        presentationTime += elapsed
        guard let art else { return }
        let world = controller.session.world
        syncTanks(art, world: world)
        syncProjectiles(art, world: world)
        syncMines(art, world: world, elapsed: elapsed)
        syncHazards(art, world: world)
        syncPickups(art, world: world)
        syncTelegraphs(art, world: world)
        syncBase(art, world: world)
        syncCurtain(world: world)
        syncCover(world: world)
        processEvents(art, world: world)
        animateLiquids(art, world: world)
        animateFoliage(art, world: world)
        updateDebugOverlay(world: world)
    }

    // MARK: - Intro curtain

    private func buildCurtain(layout: ArenaLayout, world: WorldState) {
        curtainTiles = makeTiles(layout: layout, world: world, name: "curtain")
    }

    private func makeTiles(layout: ArenaLayout, world: WorldState, name: String) -> [(cell: Vec2i, node: SKSpriteNode)] {
        let cell = SpatialUnits.subunitsPerCell
        let arena = world.arena
        var tiles: [(cell: Vec2i, node: SKSpriteNode)] = []
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                let rect = layout.sceneRect(topLeft: Vec2i(x: x * cell, y: y * cell),
                                            widthSubunits: cell, heightSubunits: cell)
                let tile = SKSpriteNode(color: .black, size: CGSize(width: rect.width + 0.5, height: rect.height + 0.5))
                tile.position = CGPoint(x: rect.midX, y: rect.midY)
                tile.zPosition = 850
                tile.name = name
                addChild(tile)
                tiles.append((Vec2i(x: x, y: y), tile))
            }
        }
        return tiles
    }

    /// Outro cover (designed transition, 2026-09-10): tiles drop from the
    /// arena edges inward — a cell is covered once its normalised distance
    /// from the centre (the larger of the x and y fractions) reaches
    /// `1 - coverStep / revealSteps`; everything is covered at the last step.
    private func syncCover(world: WorldState) {
        let step = controller.flow.coverStep
        guard coverStep != .some(step) else { return }
        coverStep = .some(step)
        guard let step else {
            for (_, node) in coverTiles { node.removeFromParent() }
            coverTiles.removeAll()
            return
        }
        if coverTiles.isEmpty, let layout { coverTiles = makeTiles(layout: layout, world: world, name: "cover") }
        let steps = max(1, controller.flow.revealSteps)
        let threshold = 1 - Double(step) / Double(steps)
        let centerX = Double(world.arena.cellsWide - 1) / 2, centerY = Double(world.arena.cellsHigh - 1) / 2
        for (cell, node) in coverTiles {
            let dx = abs(Double(cell.x) - centerX) / (centerX + 0.5)
            let dy = abs(Double(cell.y) - centerY) / (centerY + 0.5)
            node.isHidden = max(dx, dy) < threshold
        }
    }

    /// A tile is lifted once its column OR row lies within `step` strips of
    /// the arena centre; nil keeps the whole curtain down.
    private func syncCurtain(world: WorldState) {
        guard !curtainTiles.isEmpty else { return }
        let step = controller.flow.revealStep
        guard curtainStep != .some(step) else { return }
        curtainStep = .some(step)
        let centerX = Double(world.arena.cellsWide - 1) / 2, centerY = Double(world.arena.cellsHigh - 1) / 2
        for (cell, node) in curtainTiles {
            guard let step else { node.isHidden = false; continue }
            let reach = Double(step) + 0.5
            node.isHidden = abs(Double(cell.x) - centerX) <= reach || abs(Double(cell.y) - centerY) <= reach
        }
        if step == controller.flow.revealSteps {
            for (_, node) in curtainTiles { node.removeFromParent() }
            curtainTiles.removeAll()
        }
    }

    private func syncPickups(_ art: PixelArt, world: WorldState) {
        var seen = Set<Int>()
        for pickup in world.pickups {
            seen.insert(pickup.entityID)
            if pickupNodes[pickup.entityID] == nil {
                guard let catalogID = art.manifest.pickups.first(where: { $0.key == pickup.pickupID })?.id,
                      let node = try? PixelPickupNode(id: catalogID, pixelScale: artScale * 0.65, art: art)
                else { continue }
                node.position = scenePoint(pickup.positionSubunits)
                node.zPosition = 610
                addChild(node)
                pickupNodes[pickup.entityID] = (node, world.tick)
            }
            guard let entry = pickupNodes[pickup.entityID] else { continue }
            // Per-entity presentation age (first seen by this scene) — never
            // inferred from a default lifetime a restored pickup may not have.
            let age = Double(max(0, world.tick - entry.firstSeen)) / 60
            try? entry.node.update(phase: pickup.graceTicksRemaining > 0 ? .spawning : .idle, age: age)
            // Expiry warning: blink through the last five seconds (authoritative remaining time).
            entry.node.alpha = pickup.lifetimeRemainingTicks < 300 && (pickup.lifetimeRemainingTicks / 6) % 2 == 0
                ? 0.35 : 1.0
        }
        for (id, entry) in pickupNodes where !seen.contains(id) {
            entry.node.removeFromParent()
            pickupNodes[id] = nil
        }
    }

    private func syncTelegraphs(_ art: PixelArt, world: WorldState) {
        var seen = Set<Int>()
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for telegraph in world.spawnTelegraphs {
            seen.insert(telegraph.entityID)
            let center = centerPoint(telegraph.positionSubunits, size: footprint)
            let node: SKSpriteNode
            if let existing = telegraphNodes[telegraph.entityID] {
                node = existing
            } else {
                guard let created = try? art.sprite("px_prop_spawn", scale: artScale * 0.9) else { continue }
                created.zPosition = 300
                addChild(created)
                telegraphNodes[telegraph.entityID] = created
                node = created
            }
            node.position = center // deferred telegraphs can relocate
            node.alpha = 0.45 + 0.45 * abs(sin(Double(world.tick) / 8))
        }
        for (id, node) in telegraphNodes where !seen.contains(id) {
            node.removeFromParent()
            telegraphNodes[id] = nil
        }
    }

    private func syncTanks(_ art: PixelArt, world: WorldState) {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        var seen = Set<Int>()
        for tank in world.tanks {
            seen.insert(tank.entityID)
            let node: PixelTankNode
            if let existing = tankNodes[tank.entityID] {
                node = existing
            } else {
                // Archetype tier → chassis silhouette; family → turret.
                let look = PixelTankNode.appearance(archetypeID: tank.archetypeID, isPlayer: tank.ownerPlayerID != nil)
                guard let created = try? PixelTankNode(
                    kind: look.kind, weapon: look.weapon, direction: tank.facing.rawValue,
                    pixelScale: artScale, art: art) else { continue }
                created.zPosition = 500
                addChild(created)
                tankNodes[tank.entityID] = created
                tankFacings[tank.entityID] = tank.facing
                node = created
            }
            node.position = centerPoint(tank.positionSubunits, size: footprint)
            if tankFacings[tank.entityID] != tank.facing {
                tankFacings[tank.entityID] = tank.facing
                try? node.setDirection(tank.facing.rawValue)
            }
            // Equipment attachments: rebound only when the equipment changes
            // (setEquipment recreates the attachment; direction rebuilds
            // rebind it themselves).
            if tankEquipment[tank.entityID] != .some(tank.equipmentID) {
                tankEquipment[tank.entityID] = .some(tank.equipmentID)
                try? node.setEquipment(Self.equipmentArtName(tank.equipmentID))
            }
            syncShieldRing(node, art: art, shieldHP: tank.shieldHP, tick: world.tick)
            syncStatusRings(node, art: art, tank: tank, tick: world.tick)
            // Carrier tanks flash (reference rule): the blink telegraphs
            // "kill this one for its treasure". Spawn protection and
            // invincibility use rings, not alpha, so the cues never merge.
            node.alpha = tank.carriedPickupID != nil && (world.tick / 8) % 2 == 0 ? 0.55 : 1.0
            if let last = tankPositions[tank.entityID] {
                tankTravel[tank.entityID, default: 0] +=
                    abs(tank.positionSubunits.x - last.x) + abs(tank.positionSubunits.y - last.y)
            }
            tankPositions[tank.entityID] = tank.positionSubunits
            try? node.setTreadPhase(tankTravel[tank.entityID, default: 0] / 128)
        }
        for (id, node) in tankNodes where !seen.contains(id) {
            node.removeFromParent()
            tankNodes[id] = nil; tankFacings[id] = nil; tankTravel[id] = nil
            tankPositions[id] = nil; tankEquipment[id] = nil
        }

        if let player = controller.playerTank, let box = collisionBox {
            let inset = controller.session.ruleset.collisionInsetSubunits
            let a = scenePoint(Vec2i(x: player.positionSubunits.x + inset,
                                     y: player.positionSubunits.y + footprint - inset))
            let width = CGFloat(footprint - 2 * inset) * (layout?.pointsPerSubunit ?? 0)
            box.path = CGPath(rect: CGRect(x: a.x, y: a.y, width: width, height: width), transform: nil)
            box.isHidden = false
        } else {
            collisionBox?.isHidden = true
        }
    }

    /// Gameplay equipment IDs → the delivery's attachment names.
    static func equipmentArtName(_ id: String?) -> String? {
        switch id {
        case "amphi_tank": "amphi"
        case "anti_skid": "anti_skid"
        case "shield_of_moon": "moon"
        case "memory_of_sea": "memory"
        default: nil
        }
    }

    /// Pulsing shield ring on tanks with shield hit points remaining (the
    /// destructible resistance shield: `px_status_shield`).
    private func syncShieldRing(_ node: PixelTankNode, art: PixelArt, shieldHP: Int, tick: Int) {
        let name = "shield_ring"
        if shieldHP > 0 {
            let ring: SKSpriteNode
            if let existing = node.childNode(withName: name) as? SKSpriteNode {
                ring = existing
            } else {
                guard let created = try? art.sprite("px_status_shield_0", scale: artScale * 1.15)
                else { return }
                created.name = name
                created.zPosition = 6
                node.addChild(created)
                ring = created
            }
            if let frame = try? art.texture("px_status_shield_\(tick / 10 % 4)") { ring.texture = frame }
            ring.alpha = 0.7 + 0.25 * sin(Double(tick) / 9)
        } else {
            node.childNode(withName: name)?.removeFromParent()
        }
    }

    /// Distinct composites (§6.5, §12.3): spawn protection = the corner
    /// spawn ring; timed invincibility = the effect shield ring (not the
    /// destructible `px_status_shield`); frozen = the freeze glyph.
    private func syncStatusRings(_ node: PixelTankNode, art: PixelArt, tank: TankState, tick: Int) {
        func overlay(_ name: String, active: Bool, frame: String?, scale: CGFloat, z: CGFloat) {
            guard active, let frame else {
                node.childNode(withName: name)?.removeFromParent()
                return
            }
            let sprite: SKSpriteNode
            if let existing = node.childNode(withName: name) as? SKSpriteNode {
                sprite = existing
            } else {
                guard let created = try? art.sprite(frame, scale: artScale * scale) else { return }
                created.name = name
                created.zPosition = z
                node.addChild(created)
                sprite = created
            }
            if let texture = try? art.texture(frame) { sprite.texture = texture }
        }
        overlay("spawn_ring", active: tank.spawnProtectionTicks > 0,
                frame: "px_status_spawn_\(tick / 6 % 5)", scale: 1.25, z: 7)
        let shieldFrames = art.manifest.effects["shield"] ?? []
        overlay("invincible_ring", active: tank.statusEffects["invincible"] != nil,
                frame: shieldFrames.isEmpty ? nil : shieldFrames[(tick / 5) % shieldFrames.count],
                scale: 1.3, z: 9)
        overlay("freeze_overlay", active: tank.statusEffects["frozen"] != nil,
                frame: "px_status_freeze_\(tick / 10 % 5)", scale: 1.0, z: 10)
    }

    // The §10.6 danger telegraph (a tinted ring with a warning triangle over
    // AP/Explosion/Fire/Mine enemies) was removed on the owner's decision of
    // 2026-09-10 ("移除掉红圈这个设计，不需要警告"; ADR-0017). The
    // px_status_danger frames stay in the atlas, unused.

    private func syncProjectiles(_ art: PixelArt, world: WorldState) {
        var seen = Set<Int>()
        for p in world.projectiles {
            seen.insert(p.entityID)
            let node: SKSpriteNode
            if let existing = projectileNodes[p.entityID] {
                node = existing
            } else {
                // Revised art carries the per-weapon sizing; uniform scale.
                guard let created = try? art.sprite("px_projectile_" + p.weaponID, scale: artScale * 0.8)
                else { continue }
                created.zPosition = 650
                created.zRotation = -CGFloat(p.direction.rawValue) * .pi / 2
                addChild(created)
                projectileNodes[p.entityID] = created
                node = created
            }
            node.position = scenePoint(p.positionSubunits)
        }
        for (id, node) in projectileNodes where !seen.contains(id) {
            node.removeFromParent()
            projectileNodes[id] = nil
        }
    }

    private func mineSurface(_ world: WorldState, _ mine: MineState) -> PixelMineSurface {
        if mine.onWater { return .water }
        let cell = SpatialUnits.subunitsPerCell
        let cx = mine.positionSubunits.x / cell, cy = mine.positionSubunits.y / cell
        return world.terrain.isInside(cellX: cx, cellY: cy) && world.terrain[cx, cy].kind == .ice ? .ice : .ground
    }

    /// Mines through the delivery's component: ownership badge (shape, not
    /// colour), level digit, arming progress, surface overlay. Visibility
    /// policy (ADR-0010, presentation): ENEMY mines cloak once armed and
    /// only read faintly when a tank rolls near; the player's own mines
    /// never drop below 0.6 alpha. Smoothing is elapsed-time based.
    private func syncMines(_ art: PixelArt, world: WorldState, elapsed: TimeInterval) {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let cell = SpatialUnits.subunitsPerCell
        let armingTicks = max(1, controller.session.weapons.mineArmingTicks)
        var seen = Set<Int>()
        for mine in world.mines {
            seen.insert(mine.entityID)
            let surface = mineSurface(world, mine)
            if let existing = mineNodes[mine.entityID], existing.surface != surface {
                existing.node.removeFromParent() // ice melted under it: re-dress the surface
                mineNodes[mine.entityID] = nil
            }
            if mineNodes[mine.entityID] == nil {
                guard let node = try? PixelMineNode(
                    level: mine.level, owner: mine.ownerPlayerID != nil ? "player" : "enemy",
                    surface: surface, pixelScale: artScale * 0.65, art: art) else { continue }
                node.position = scenePoint(mine.positionSubunits)
                node.zPosition = 600
                node.alpha = 1
                addChild(node)
                mineNodes[mine.entityID] = (node, surface, world.tick)
            }
            guard let entry = mineNodes[mine.entityID] else { continue }
            let age = Double(max(0, world.tick - entry.firstSeen)) / 60
            let progress = mine.phase == .arming
                ? max(0, min(1, 1 - Double(mine.phaseTicksRemaining) / Double(armingTicks))) : 1
            try? entry.node.update(phase: mine.phase == .arming ? .arming : .armed, age: age, progress: progress)

            var targetAlpha: CGFloat = 1
            if mine.phase == .armed {
                var nearest = Int.max
                for tank in world.tanks {
                    let dx = tank.positionSubunits.x + footprint / 2 - mine.positionSubunits.x
                    let dy = tank.positionSubunits.y + footprint / 2 - mine.positionSubunits.y
                    nearest = min(nearest, max(abs(dx), abs(dy)))
                }
                targetAlpha = nearest < 2 * cell ? 0.55 : nearest < 4 * cell ? 0.3 : 0.0
                if mine.ownerPlayerID != nil { targetAlpha = max(0.6, targetAlpha) }
            }
            let rate = min(1, elapsed * 7) // ≈ 0.12 per frame at 60 Hz, half that at 120 Hz
            entry.node.alpha += (targetAlpha - entry.node.alpha) * rate
        }
        for (id, entry) in mineNodes where !seen.contains(id) {
            entry.node.removeFromParent()
            mineNodes[id] = nil
        }
    }

    private func syncHazards(_ art: PixelArt, world: WorldState) {
        var seen = Set<Int>()
        let frames = art.manifest.effects["fire"] ?? []
        for hazard in world.fireHazards {
            seen.insert(hazard.entityID)
            let node: SKSpriteNode
            if let existing = hazardNodes[hazard.entityID] {
                node = existing
            } else {
                guard let first = frames.first, let created = try? art.sprite(first, scale: artScale)
                else { continue }
                created.position = scenePoint(hazard.positionSubunits)
                created.zPosition = 620
                addChild(created)
                hazardNodes[hazard.entityID] = created
                node = created
            }
            if !frames.isEmpty {
                let frame = (world.tick / 8 + hazard.entityID) % frames.count
                node.texture = try? art.texture(frames[frame])
            }
        }
        for (id, node) in hazardNodes where !seen.contains(id) {
            node.removeFromParent()
            hazardNodes[id] = nil
        }
    }

    private func syncBase(_ art: PixelArt, world: WorldState) {
        guard let base = world.base else { return }
        if baseNode == nil {
            let pixelScale = artScale
            baseNode = try? PixelBaseNode(pixelScale: pixelScale, art: art)
            if let baseNode {
                // The base art's node origin is its GROUND anchor (source
                // y=35 of 64; visual bottom edge at y=54). Place it so the
                // art's bottom edge sits on the footprint's bottom cell
                // edge — centered on the rect it would float (owner report).
                let bottom = scenePoint(Vec2i(
                    x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                    y: base.topLeftSubunits.y + base.sizeSubunits))
                baseNode.position = CGPoint(x: bottom.x, y: bottom.y + (54 - 35) * pixelScale)
                baseNode.zPosition = 400
                addChild(baseNode)
            }
        }
        let shielded = base.shieldRemainingTicks > 0
        if shielded && !wasShielded { shieldActivatedTick = world.tick } // live activation edge only
        wasShielded = shielded
        let phase: PixelBaseShieldPhase
        var age = Double(world.tick) / 60
        if !shielded {
            phase = .absent
        } else if base.shieldRemainingTicks < 180 {
            phase = .warning
        } else if let started = shieldActivatedTick, world.tick - started < 24 {
            phase = .appearing
            age = Double(world.tick - started) / 60
        } else {
            phase = .active
        }
        // Durability 3/2/1/0 maps to the four visual states (§6.6).
        let state = max(0, min(3, base.maxDurability - base.durability))
        try? baseNode?.update(damageState: state, shieldPhase: phase, age: age)
    }

    // MARK: - Events → transient presentation

    /// ADR-0005 own-fire cue: a tinted silhouette of the base's current
    /// damage state — the player's teal for an allied hit, red for an enemy
    /// breakthrough — fading out over the flash. The tint is applied to the
    /// overlay SPRITE directly (not through a colorize action on the vendor
    /// node), so it is visible and testable.
    func flashBase(_ art: PixelArt, allied: Bool, damageState: Int) {
        guard let baseNode else { return }
        baseFlash?.removeFromParent()
        let stateID = art.manifest.baseStates[max(0, min(art.manifest.baseStates.count - 1, damageState))]
        guard let overlay = try? art.sprite(stateID, scale: artScale) else { return }
        overlay.position = baseNode.position
        overlay.zPosition = baseNode.zPosition + 1
        overlay.color = allied
            ? SKColor(red: 0.2, green: 0.9, blue: 0.8, alpha: 1)
            : SKColor(red: 1, green: 0.2, blue: 0.15, alpha: 1)
        overlay.colorBlendFactor = 0.85
        overlay.alpha = 0.9
        overlay.name = allied ? "base_flash_allied" : "base_flash_enemy"
        addChild(overlay)
        overlay.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        baseFlash = overlay
    }

    /// Muzzle position for a `weaponFired` event, anchored to the EVENT's
    /// footprint and facing (historical), never to where the shooter's node
    /// is now. The live rig contributes only its facing-specific muzzle
    /// offset; a missing or turned node falls back to the geometric muzzle.
    func muzzleScenePoint(entityID: Int, position: Vec2i, facing: Direction) -> CGPoint {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let center = Vec2i(x: position.x + footprint / 2, y: position.y + footprint / 2)
        let anchor = scenePoint(center)
        if let node = tankNodes[entityID], node.direction == facing.rawValue {
            let live = node.muzzle(in: self)
            return CGPoint(x: anchor.x + (live.x - node.position.x), y: anchor.y + (live.y - node.position.y))
        }
        return scenePoint(center + facing.vector * (footprint / 2))
    }

    private func spawnEffect(_ art: PixelArt, kind: PixelEffectKind, at point: CGPoint,
                             scale: CGFloat = 1, z: CGFloat = 700) {
        guard let fx = try? PixelEffectNode(kind: kind, pixelScale: artScale * scale, art: art) else { return }
        fx.position = point
        fx.zPosition = z
        addChild(fx)
        transientEffects.append((fx, presentationTime))
        if transientEffects.count > Self.maxTransientEffects {
            transientEffects.removeFirst().node.stop()
        }
    }

    /// Burned grass where foliage burned away: a decal on the ground layer,
    /// bounded like the scorch marks (oldest dropped first).
    private var burnedGrassNodes: [SKSpriteNode] = []
    private static let maxBurnedGrassDecals = 96

    private func addBurnedGrass(_ art: PixelArt, cellX: Int, cellY: Int) {
        guard let decal = try? art.sprite("px_foliage_burned", scale: artScale) else { return }
        decal.position = cellCenter(x: cellX, y: cellY)
        decal.zPosition = 10
        addChild(decal)
        burnedGrassNodes.append(decal)
        if burnedGrassNodes.count > Self.maxBurnedGrassDecals { burnedGrassNodes.removeFirst().removeFromParent() }
    }

    private func addScorch(_ art: PixelArt, world: WorldState, at position: Vec2i, index: Int) {
        let cell = SpatialUnits.subunitsPerCell
        let cx = position.x / cell, cy = position.y / cell
        guard world.terrain.isInside(cellX: cx, cellY: cy) else { return }
        let kind = world.terrain[cx, cy].kind
        guard kind != .water && kind != .ice else { return } // no soot on liquids
        guard let decal = try? art.sprite("px_decal_scorch_\(abs(index) % 3)", scale: artScale) else { return }
        decal.position = scenePoint(position)
        decal.zPosition = 10
        decal.alpha = 0.75
        addChild(decal)
        scorchNodes.append(decal)
        if scorchNodes.count > Self.maxScorchDecals { scorchNodes.removeFirst().removeFromParent() }
    }

    /// Consumes domain events for transient presentation. Every position
    /// comes from the payload (anchors documented on `DomainEvent`), so an
    /// entity that vanished earlier in the drained batch still gets its
    /// effect in the right place.
    private func processEvents(_ art: PixelArt, world: WorldState) {
        let drained = controller.drainEvents()
        audio.play(events: drained)
        haptics.play(events: drained)
        // Burning ambience while any flame patch is alive.
        audio.setLoop("sfx_flame_loop", active: !world.fireHazards.isEmpty
                      && (world.stage == nil || world.stage?.phase == .playing))
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for event in drained {
            switch event {
            case .terrainChanged(let cx, let cy, _):
                let key = cy * world.arena.cellsWide + cx
                let wasFoliage = foliageNodes[key] != nil
                reconcileTerrainCell(art, world: world, cellX: cx, cellY: cy)
                if wasFoliage, world.terrain.isInside(cellX: cx, cellY: cy), world.terrain[cx, cy].kind == .ground {
                    addBurnedGrass(art, cellX: cx, cellY: cy) // burned away (ADR-0017)
                }
                for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)]
                where world.terrain.isInside(cellX: cx + dx, cellY: cy + dy) {
                    refreshWallTexture(art, world: world, cellX: cx + dx, cellY: cy + dy)
                }
            case .explosion(let position, let radius):
                spawnEffect(art, kind: .groundExplosion, at: scenePoint(position),
                            scale: radius > 1200 ? 1.2 : 0.85)
                addScorch(art, world: world, at: position, index: position.x / 97 + position.y / 89)
            case .tankDestroyed(_, _, let position):
                spawnEffect(art, kind: .tankExplosion, at: centerPoint(position, size: footprint))
            case .tankDamaged(_, _, _, _, let position):
                spawnEffect(art, kind: .armorHit, at: centerPoint(position, size: footprint), scale: 0.8)
            case .tankShieldHit(_, _, _, let position):
                spawnEffect(art, kind: .shieldHit, at: centerPoint(position, size: footprint))
            case .projectileHit(_, _, let position, let impact),
                 .projectileDestroyed(_, _, let position, let impact):
                let kind: PixelEffectKind? = switch impact {
                case .brick: .brickHit
                case .steel, .boundary: .steelHit
                case .deflected: .shieldHit
                case .projectile, .mine: .projectileCancel
                case .base: .baseHit
                case .tank, .expired, .explosion: nil // damage/blast events carry the effect
                }
                if let kind { spawnEffect(art, kind: kind, at: scenePoint(position), scale: 0.7, z: 680) }
            case .mineRemoved(_, let position):
                spawnEffect(art, kind: .mineDisarm, at: scenePoint(position), scale: 0.7)
            case .mineTriggered(_, let position):
                spawnEffect(art, kind: .mineTrigger, at: scenePoint(position), scale: 0.8)
            case .pickupCollected(_, _, _, let position):
                spawnEffect(art, kind: .pickupCollect, at: scenePoint(position), scale: 0.8)
            case .baseShieldChanged(let active):
                if let baseNode {
                    spawnEffect(art, kind: active ? .baseShieldAppear : .baseShieldEnd,
                                at: baseNode.position, scale: 1.1, z: 690)
                }
            case .baseDamaged(_, let remaining, let allied):
                // ADR-0005: own fire is never mistaken for a breakthrough —
                // the structure flashes the player's teal, an enemy hit red.
                if let baseNode {
                    let state = max(0, min(3, (world.base?.maxDurability ?? 3) - remaining))
                    flashBase(art, allied: allied, damageState: state)
                    spawnEffect(art, kind: .baseHit, at: baseNode.position, scale: 1.0, z: 690)
                }
            case .tankLaunched(let entityID, _, _, _):
                // Mine launch (§8.6): the tank lifts (scale) for its flight; the
                // landing resets it. SKActions park with the scene on pause.
                if let node = tankNodes[entityID] {
                    node.removeAction(forKey: "flight")
                    let up = SKAction.scale(to: 1.35, duration: 0.18)
                    let down = SKAction.scale(to: 1.0, duration: 0.22)
                    node.run(SKAction.sequence([up, down]), withKey: "flight")
                }
            case .tankLanded(let entityID, _, _):
                if let node = tankNodes[entityID] {
                    node.removeAction(forKey: "flight")
                    node.setScale(1)
                }
            case .tankSpawned(_, let owner, let position, _) where owner != nil:
                spawnEffect(art, kind: .spawnComplete, at: centerPoint(position, size: footprint))
            case .weaponFired(let entityID, _, let weaponID, _, let position, let facing):
                guard weaponID != "mine", weaponID != "fire" else { break }
                let effectName = weaponID == "normal" ? "muzzle" : weaponID
                guard let frames = art.manifest.effects[effectName], let first = frames.first,
                      let flash = try? art.sprite(first, scale: artScale * 0.48) else { break }
                flash.position = muzzleScenePoint(entityID: entityID, position: position, facing: facing)
                flash.zPosition = 660
                // Tanks swap directional textures; their node rotation stays zero.
                flash.zRotation = -CGFloat(facing.rawValue) * .pi / 2
                addChild(flash)
                flash.run(.sequence([.wait(forDuration: 0.1), .removeFromParent()]))
            default:
                break
            }
        }
        var kept: [(PixelEffectNode, TimeInterval)] = []
        for (fx, born) in transientEffects {
            let age = presentationTime - born
            if age > fx.duration + 0.05 {
                fx.stop()
            } else {
                try? fx.advance(to: age)
                kept.append((fx, born))
            }
        }
        transientEffects = kept
    }

    private func animateLiquids(_ art: PixelArt, world: WorldState) {
        let frame = (world.tick / 15) % 4
        let width = world.arena.cellsWide
        for (key, entry) in liquidNodes {
            let cx = key % width, cy = key / width
            let expected: TerrainKind = entry.kind == "water" ? .water : .ice
            guard world.terrain.isInside(cellX: cx, cellY: cy),
                  world.terrain[cx, cy].kind == expected else {
                entry.node.removeFromParent() // melted/removed (fire on ice)
                liquidNodes[key] = nil
                continue
            }
            var mask = 0
            let offsets = [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0),
                           (16, 1, -1), (32, 1, 1), (64, -1, 1), (128, -1, -1)]
            for (bit, dx, dy) in offsets
            where world.terrain.isInside(cellX: cx + dx, cellY: cy + dy)
                && world.terrain[cx + dx, cy + dy].kind == expected { mask |= bit }
            for (diag, a, b) in [(16, 1, 2), (32, 2, 4), (64, 4, 8), (128, 8, 1)]
            where mask & a == 0 || mask & b == 0 { mask &= ~diag }
            if let texture = try? art.texture(String(format: "px_%@_%03d_%d", entry.kind, mask, frame)) {
                entry.node.texture = texture
            }
        }
    }

    private func updateDebugOverlay(world: WorldState) {
        guard debugLabel != nil else { return } // lab only: no per-frame checksum otherwise
        guard let tank = controller.playerTank else {
            debugLabel?.text = "M2 COMBAT LAB  tick \(world.tick)  respawning…"
            return
        }
        debugLabel?.text = String(
            format: "M2 COMBAT LAB  tick %d  %@ ammo %d  pwr %d  proj %d  mines %d  base %d  checksum %llx",
            world.tick, tank.specialWeaponID, controller.currentAmmo, tank.powerLevel,
            world.projectiles.count, world.mines.count, world.base?.durability ?? 0,
            world.checksum())
    }
}
