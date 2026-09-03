import SpriteKit
import GameApplication
import GameCore

/// M1 Movement Lab renderer: draws the lab fixture with PixelProduction art
/// and mirrors the authoritative world each frame. Render-only — the
/// simulation is advanced exclusively by the display-link driver
/// (ADR-0007); this scene never steps, pauses, or gates ticks.
final class MovementLabScene: SKScene {
    private let controller: MovementLabController
    private var art: PixelArt?
    private var tankNode: PixelTankNode?
    private var debugLabel: SKLabelNode?
    private var collisionBox: SKShapeNode?
    private var liquidSprites: [(node: SKSpriteNode, kind: String, mask: Int)] = []
    private var lastFacing: Direction = .down
    private var travelledSubunits = 0
    private var lastPosition: Vec2i?

    private var layout: ArenaLayout?
    private var cellPoints: CGFloat = 0
    private var originPoint: CGPoint = .zero
    private var pointsPerSubunit: CGFloat = 0

    init(size: CGSize, controller: MovementLabController) {
        self.controller = controller
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic scene") }

    override func didMove(to view: SKView) {
        removeAllChildren()
        liquidSprites.removeAll()
        let world = controller.session.world
        // Edge-to-edge uniform fit (ADR-0004): no reserved margins; the HUD
        // overlays the arena and stays safe-area-aware.
        let layout = ArenaLayout(surface: size, arena: world.arena)
        self.layout = layout
        cellPoints = layout.cellPoints
        originPoint = layout.origin
        pointsPerSubunit = layout.pointsPerSubunit
        do {
            let art = try PixelArt()
            self.art = art
            try buildTerrain(art, world: world)
            try buildTank(art, world: world)
            buildDebugOverlay()
        } catch {
            let n = SKLabelNode(fontNamed: "Menlo-Bold")
            n.text = "asset load failed: \(error)"
            n.fontSize = 14; n.fontColor = .red
            n.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(n)
        }
    }

    /// World subunits (Y-down) → scene points (Y-up), via the shared layout.
    private func scenePoint(_ p: Vec2i) -> CGPoint {
        layout?.scenePoint(p) ?? .zero
    }

    private func buildTerrain(_ art: PixelArt, world: WorldState) throws {
        let arena = world.arena
        let artScale = cellPoints / 16

        for y in stride(from: 0, to: arena.cellsHigh, by: 3) {
            for x in stride(from: 0, to: arena.cellsWide, by: 3) {
                let n = try art.sprite("px_ground_frontier_\((x / 3 + y / 3) % 9)", scale: artScale)
                n.position = cellCenter(x: x, y: y, span: 3)
                n.size = CGSize(width: cellPoints * 3, height: cellPoints * 3)
                n.zPosition = 0
                addChild(n)
            }
        }

        func kindAt(_ x: Int, _ y: Int) -> TerrainKind? {
            world.terrain.isInside(cellX: x, cellY: y) ? world.terrain[x, y].kind : nil
        }
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                let kind = world.terrain[x, y].kind
                switch kind {
                case .brick, .steel:
                    let name = kind == .brick ? "brick" : "steel"
                    var mask = 0
                    for (bit, dx, dy) in [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0)]
                    where kindAt(x + dx, y + dy) == kind { mask |= bit }
                    let n = try art.sprite(String(format: "px_%@_joint_%02d_15", name, mask), scale: artScale)
                    n.position = cellCenter(x: x, y: y)
                    n.zPosition = 100
                    addChild(n)
                case .water, .ice:
                    let name = kind == .water ? "water" : "ice"
                    var mask = 0
                    let offsets = [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0),
                                   (16, 1, -1), (32, 1, 1), (64, -1, 1), (128, -1, -1)]
                    for (bit, dx, dy) in offsets where kindAt(x + dx, y + dy) == kind { mask |= bit }
                    for (diag, a, b) in [(16, 1, 2), (32, 2, 4), (64, 4, 8), (128, 8, 1)]
                    where mask & a == 0 || mask & b == 0 { mask &= ~diag }
                    let n = try art.sprite(String(format: "px_%@_%03d_0", name, mask), scale: artScale)
                    n.position = cellCenter(x: x, y: y)
                    n.zPosition = 5
                    addChild(n)
                    liquidSprites.append((n, name, mask))
                case .ground, .foliage, .base:
                    break
                }
            }
        }
    }

    private func cellCenter(x: Int, y: Int, span: Int = 1) -> CGPoint {
        scenePoint(Vec2i(x: x * SpatialUnits.subunitsPerCell + span * SpatialUnits.subunitsPerCell / 2,
                         y: y * SpatialUnits.subunitsPerCell + span * SpatialUnits.subunitsPerCell / 2))
    }

    private func buildTank(_ art: PixelArt, world: WorldState) throws {
        let tank = try PixelTankNode(kind: "player", weapon: "normal", direction: 2,
                                     pixelScale: cellPoints / 16 * 0.82, art: art)
        tank.zPosition = 500
        addChild(tank)
        tankNode = tank

        let box = SKShapeNode()
        box.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.9)
        box.lineWidth = 1
        box.zPosition = 900
        addChild(box)
        collisionBox = box
    }

    private func buildDebugOverlay() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 10
        label.fontColor = SKColor(white: 1, alpha: 0.8)
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: originPoint.x + 8, y: size.height - 16)
        label.zPosition = 9000
        addChild(label)
        debugLabel = label
    }

    /// Presentation update only: read the latest snapshot and mirror it.
    override func update(_ currentTime: TimeInterval) {
        guard let tankNode, let tank = controller.session.world.tanks.first else { return }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let center = Vec2i(x: tank.positionSubunits.x + footprint / 2,
                           y: tank.positionSubunits.y + footprint / 2)
        tankNode.position = scenePoint(center)

        if tank.facing != lastFacing {
            lastFacing = tank.facing
            try? tankNode.setDirection(tank.facing.rawValue)
        }
        if let last = lastPosition {
            travelledSubunits += abs(tank.positionSubunits.x - last.x) + abs(tank.positionSubunits.y - last.y)
        }
        lastPosition = tank.positionSubunits
        try? tankNode.setTreadPhase(travelledSubunits / 128)

        if let box = collisionBox {
            let inset = controller.session.ruleset.collisionInsetSubunits
            let a = scenePoint(Vec2i(x: tank.positionSubunits.x + inset, y: tank.positionSubunits.y + footprint - inset))
            let width = CGFloat(footprint - 2 * inset) * pointsPerSubunit
            box.path = CGPath(rect: CGRect(x: a.x, y: a.y, width: width, height: width), transform: nil)
        }

        let world = controller.session.world
        let frame = (world.tick / 15) % 4
        for (node, kind, mask) in liquidSprites {
            node.texture = try? art?.texture(String(format: "px_%@_%03d_%d", kind, mask, frame))
        }
        debugLabel?.text = String(
            format: "M1 MOVEMENT LAB  tick %d  pos (%d,%d)  facing %@  buf %@  checksum %llx",
            world.tick, tank.positionSubunits.x, tank.positionSubunits.y,
            String(describing: tank.facing), tank.bufferedDirection.map { String(describing: $0) } ?? "-",
            world.checksum())
    }
}
