import SpriteKit
import GameApplication
import GameCore

/// M1/M2 Combat Lab renderer: draws the lab fixture with PixelProduction
/// art and mirrors the authoritative world each frame. Render-only — the
/// simulation is advanced exclusively by the display-link driver
/// (ADR-0007); this scene never steps, pauses, or gates ticks.
final class MovementLabScene: SKScene {
    private let controller: MovementLabController
    private var art: PixelArt?
    private var debugLabel: SKLabelNode?
    private var collisionBox: SKShapeNode?
    /// Liquid tiles keyed by cell index; re-tiled every frame from the
    /// live terrain so melting ice heals edges automatically.
    private var liquidNodes: [Int: (node: SKSpriteNode, kind: String)] = [:]
    private var layout: ArenaLayout?

    // Dynamic mirrors keyed by entity ID.
    private var tankNodes: [Int: PixelTankNode] = [:]
    private var tankFacings: [Int: Direction] = [:]
    private var tankTravel: [Int: Int] = [:]
    private var tankPositions: [Int: Vec2i] = [:]
    private var projectileNodes: [Int: SKSpriteNode] = [:]
    private var mineNodes: [Int: (node: SKSpriteNode, phase: MinePhase)] = [:]
    private var hazardNodes: [Int: SKSpriteNode] = [:]
    private var wallNodes: [Int: SKSpriteNode] = [:]
    private var pickupNodes: [Int: PixelPickupNode] = [:]
    private var telegraphNodes: [Int: SKSpriteNode] = [:]
    private var baseNode: PixelBaseNode?
    private var transientEffects: [(node: PixelEffectNode, born: Int)] = []
    private var builtGeneration = -1

    private var cellPoints: CGFloat = 0
    private var artScale: CGFloat = 0

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

    private func rebuildWorldView() {
        builtGeneration = controller.worldGeneration
        removeAllChildren()
        liquidNodes.removeAll(); tankNodes.removeAll(); projectileNodes.removeAll()
        mineNodes.removeAll(); hazardNodes.removeAll(); wallNodes.removeAll()
        pickupNodes.removeAll(); telegraphNodes.removeAll()
        tankFacings.removeAll(); tankTravel.removeAll(); tankPositions.removeAll()
        transientEffects.removeAll(); baseNode = nil
        let world = controller.session.world
        let layout = ArenaLayout(surface: size, arena: world.arena)
        self.layout = layout
        cellPoints = layout.cellPoints
        artScale = cellPoints / 16
        do {
            let art = try PixelArt()
            self.art = art
            try buildTerrain(art, world: world)
            buildDebugOverlay()
        } catch {
            let n = SKLabelNode(fontNamed: "Menlo-Bold")
            n.text = "asset load failed: \(error)"
            n.fontSize = 14; n.fontColor = .red
            n.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(n)
        }
    }

    private func scenePoint(_ p: Vec2i) -> CGPoint { layout?.scenePoint(p) ?? .zero }

    private func centerPoint(_ topLeft: Vec2i, size sizeSubunits: Int) -> CGPoint {
        scenePoint(Vec2i(x: topLeft.x + sizeSubunits / 2, y: topLeft.y + sizeSubunits / 2))
    }

    // MARK: - Static terrain

    private func buildTerrain(_ art: PixelArt, world: WorldState) throws {
        let arena = world.arena
        for y in stride(from: 0, to: arena.cellsHigh, by: 3) {
            for x in stride(from: 0, to: arena.cellsWide, by: 3) {
                let n = try art.sprite("px_ground_frontier_\((x / 3 + y / 3) % 9)", scale: artScale)
                n.position = cellCenter(x: x, y: y, span: 3)
                n.size = CGSize(width: cellPoints * 3, height: cellPoints * 3)
                n.zPosition = 0
                addChild(n)
            }
        }
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                switch world.terrain[x, y].kind {
                case .brick, .steel:
                    let n = SKSpriteNode()
                    n.size = CGSize(width: cellPoints, height: cellPoints)
                    n.position = cellCenter(x: x, y: y)
                    n.zPosition = 100
                    addChild(n)
                    wallNodes[y * arena.cellsWide + x] = n
                    refreshWallTexture(art, world: world, cellX: x, cellY: y)
                case .water, .ice:
                    let name = world.terrain[x, y].kind == .water ? "water" : "ice"
                    let n = try art.sprite(String(format: "px_%@_000_0", name), scale: artScale)
                    n.position = cellCenter(x: x, y: y)
                    n.zPosition = 5
                    addChild(n)
                    liquidNodes[y * arena.cellsWide + x] = (n, name)
                case .ground, .foliage, .base:
                    break
                }
            }
        }
    }

    private func refreshWallTexture(_ art: PixelArt, world: WorldState, cellX: Int, cellY: Int) {
        let key = cellY * world.arena.cellsWide + cellX
        guard let node = wallNodes[key] else { return }
        let cell = world.terrain[cellX, cellY]
        guard cell.kind == .brick || cell.kind == .steel, cell.quadrantMask != 0 else {
            node.removeFromParent()
            wallNodes[key] = nil
            return
        }
        let name = cell.kind == .brick ? "brick" : "steel"
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
        guard let art else { return }
        let world = controller.session.world
        syncTanks(art, world: world)
        syncProjectiles(art, world: world)
        syncMines(art, world: world)
        syncHazards(art, world: world)
        syncPickups(art, world: world)
        syncTelegraphs(art, world: world)
        syncBase(art, world: world)
        processEvents(art, world: world)
        animateLiquids(art, world: world)
        updateDebugOverlay(world: world)
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
                pickupNodes[pickup.entityID] = node
            }
            try? pickupNodes[pickup.entityID]?.update(
                phase: pickup.graceTicksRemaining > 0 ? .spawning : .idle,
                age: Double(world.tick % 600) / 60)
        }
        for (id, node) in pickupNodes where !seen.contains(id) {
            node.removeFromParent()
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
                let kind: String
                let weapon: String
                if tank.ownerPlayerID != nil {
                    kind = "player"; weapon = "normal"
                } else {
                    let parts = tank.archetypeID.split(separator: "_").map(String.init)
                    kind = switch parts.last ?? "a" {
                    case "b": "standard"
                    case "c": "armored"
                    case "d": "heavy"
                    default: "scout"
                    }
                    weapon = ["normal", "rapid", "fire", "ap", "explosion", "mine"]
                        .contains(parts.first ?? "") ? parts.first! : "normal"
                }
                guard let created = try? PixelTankNode(
                    kind: kind, weapon: weapon, direction: tank.facing.rawValue,
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
            syncShieldRing(node, art: art, shieldHP: tank.shieldHP, tick: world.tick)
            if let last = tankPositions[tank.entityID] {
                tankTravel[tank.entityID, default: 0] +=
                    abs(tank.positionSubunits.x - last.x) + abs(tank.positionSubunits.y - last.y)
            }
            tankPositions[tank.entityID] = tank.positionSubunits
            try? node.setTreadPhase(tankTravel[tank.entityID, default: 0] / 128)
        }
        for (id, node) in tankNodes where !seen.contains(id) {
            node.removeFromParent()
            tankNodes[id] = nil; tankFacings[id] = nil; tankTravel[id] = nil; tankPositions[id] = nil
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

    /// Pulsing shield ring on tanks with shield hit points remaining.
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

    private func syncMines(_ art: PixelArt, world: WorldState) {
        var seen = Set<Int>()
        for mine in world.mines {
            seen.insert(mine.entityID)
            if let existing = mineNodes[mine.entityID] {
                if existing.phase != mine.phase {
                    existing.node.texture = try? art.texture(
                        "px_mine_\(mine.level)_" + (mine.phase == .armed ? "armed" : "dormant"))
                    mineNodes[mine.entityID] = (existing.node, mine.phase)
                }
            } else {
                guard let node = try? art.sprite(
                    "px_mine_\(mine.level)_" + (mine.phase == .armed ? "armed" : "dormant"),
                    scale: artScale * 0.65) else { continue }
                node.position = scenePoint(mine.positionSubunits)
                node.zPosition = 600
                addChild(node)
                mineNodes[mine.entityID] = (node, mine.phase)
            }
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
        // Damage quarters map to the four visual states.
        let state = base.durability > 75 ? 0 : base.durability > 40 ? 1 : base.durability > 0 ? 2 : 3
        try? baseNode?.update(
            damageState: state,
            shieldPhase: base.shieldRemainingTicks > 0 ? .active : .absent,
            age: Double(world.tick) / 60)
    }

    /// Consumes domain events for transient presentation: explosions,
    /// muzzle flashes, and terrain texture refreshes.
    private func processEvents(_ art: PixelArt, world: WorldState) {
        for event in controller.drainEvents() {
            switch event {
            case .terrainChanged(let cx, let cy, _):
                refreshWallTexture(art, world: world, cellX: cx, cellY: cy)
                for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)]
                where world.terrain.isInside(cellX: cx + dx, cellY: cy + dy) {
                    refreshWallTexture(art, world: world, cellX: cx + dx, cellY: cy + dy)
                }
            case .explosion(let position, let radius):
                if let fx = try? PixelEffectNode(kind: .groundExplosion,
                                                 pixelScale: artScale * (radius > 1200 ? 1.2 : 0.85),
                                                 art: art) {
                    fx.position = scenePoint(position)
                    fx.zPosition = 700
                    addChild(fx)
                    transientEffects.append((fx, world.tick))
                }
            case .tankDestroyed(_, let position):
                if let fx = try? PixelEffectNode(kind: .tankExplosion, pixelScale: artScale, art: art) {
                    fx.position = centerPoint(position, size: SpatialUnits.standardTankFootprintSubunits)
                    fx.zPosition = 700
                    addChild(fx)
                    transientEffects.append((fx, world.tick))
                }
            case .weaponFired(let entityID, let weaponID, _, _):
                guard weaponID != "mine", weaponID != "fire",
                      let tankNode = tankNodes[entityID] else { break }
                let effectName = weaponID == "normal" ? "muzzle" : weaponID
                if let frames = art.manifest.effects[effectName], let first = frames.first,
                   let flash = try? art.sprite(first, scale: artScale * 0.48) {
                    flash.position = tankNode.muzzle(in: self)
                    flash.zPosition = 660
                    flash.zRotation = tankNode.zRotation
                    addChild(flash)
                    flash.run(.sequence([.wait(forDuration: 0.1), .removeFromParent()]))
                }
            default:
                break
            }
        }
        var kept: [(PixelEffectNode, Int)] = []
        for (fx, born) in transientEffects {
            let age = Double(world.tick - born) / 60
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
