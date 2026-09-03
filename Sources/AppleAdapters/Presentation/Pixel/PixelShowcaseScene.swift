import SpriteKit

/// iOS port of the PixelProduction delivery's verified macOS render fixture
/// (`Tools/RenderPixel.swift`): the complete fixed 48×27 arena, the tank
/// roster, the four-direction rig, and an item sheet — composed from the
/// shipped atlases through the delivery's own runtime (PixelArt/PixelTankNode
/// et al.). Scripted art fixture only: no rules, no collision, no authority.
final class PixelShowcaseScene: SKScene {
    enum Mode { case battle, roster, directions, items }

    private let mode: Mode
    private var art: PixelArt?
    private var startTime: TimeInterval?
    private var phase = -1

    // Animated references kept across ticks.
    private var tanks: [PixelTankNode] = []
    private var rosterDirection = 0
    private var liquidSprites: [(node: SKSpriteNode, kind: String, mask: Int)] = []
    private var pickups: [PixelPickupNode] = []
    private var effects: [PixelEffectNode] = []
    private var baseNode: PixelBaseNode?
    private var dynamicLayer = SKNode()

    // Battle-mode geometry shared between build and tick.
    private var cell: CGFloat = 0, artScale: CGFloat = 0
    private var origin: CGPoint = .zero
    private var arenaRect: CGRect = .zero
    private let tankSpecs: [(kind: String, weapon: String, dir: Int, x: CGFloat, y: CGFloat)] = [
        ("player", "normal", 0, 19, 22), ("scout", "normal", 2, 9, 3.3),
        ("standard", "rapid", 2, 23, 3.2), ("armored", "fire", 3, 37, 8),
        ("heavy", "ap", 3, 41, 17), ("scout", "mine", 1, 12, 15),
        ("standard", "explosion", 0, 32, 21), ("scout", "normal", 0, 6, 22),
        ("heavy", "fire", 1, 23, 14),
    ]

    init(size: CGSize, mode: Mode) {
        self.mode = mode
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic scene") }

    override func didMove(to view: SKView) {
        removeAllChildren()
        tanks.removeAll(); liquidSprites.removeAll(); pickups.removeAll(); effects.removeAll()
        do {
            let art = try PixelArt()
            self.art = art
            switch mode {
            case .battle: try buildArena(art)
            case .roster: try buildRoster(art)
            case .directions: try buildDirections(art)
            case .items: try buildItems(art)
            }
        } catch {
            let n = SKLabelNode(fontNamed: "Menlo-Bold")
            n.text = "PixelProduction load failed: \(error)"
            n.fontSize = 14; n.fontColor = .red
            n.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(n)
        }
    }

    // MARK: - Shared helpers

    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat,
                       _ font: CGFloat = 12, _ color: SKColor = .white, in parent: SKNode? = nil) {
        let n = SKLabelNode(fontNamed: "Menlo-Bold")
        n.text = text; n.fontSize = font; n.fontColor = color
        n.position = CGPoint(x: x, y: y); n.zPosition = 9200
        (parent ?? self).addChild(n)
    }

    @discardableResult
    private func sprite(_ art: PixelArt, _ id: String, _ p: CGPoint, _ scale: CGFloat,
                        _ z: CGFloat = 0, in parent: SKNode? = nil) throws -> SKSpriteNode {
        let n = try art.sprite(id, scale: scale)
        n.position = p; n.zPosition = z
        (parent ?? self).addChild(n)
        return n
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * cell, y: origin.y + (27 - y) * cell)
    }

    // MARK: - Arena / battle fixture

    private func buildArena(_ art: PixelArt) throws {
        let columns = 48, rows = 27
        cell = min((size.width - 28) / CGFloat(columns), (size.height - 34) / CGFloat(rows))
        let width = CGFloat(columns) * cell, height = CGFloat(rows) * cell
        origin = CGPoint(x: (size.width - width) / 2, y: 10 + (size.height - 34 - height) / 2)
        arenaRect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        artScale = cell / 16

        for y in stride(from: 0, to: rows, by: 3) {
            for x in stride(from: 0, to: columns, by: 3) {
                let n = try sprite(art, "px_ground_frontier_\((x / 3 + y / 3) % 9)",
                                   point(CGFloat(x) + 1.5, CGFloat(y) + 1.5), artScale, 0)
                n.size = CGSize(width: cell * 3, height: cell * 3)
            }
        }

        var solids = Set<String>()
        var wallNodes: [String: (SKSpriteNode, String, Int)] = [:]
        func wall(_ x: Int, _ y: Int, _ kind: String = "brick", _ remaining: Int = 15) throws {
            let id = remaining == 15 ? "px_\(kind)_connected_00"
                                     : String(format: "px_%@_remaining_%02d", kind, remaining)
            let n = try sprite(art, id, point(CGFloat(x) + 0.5, CGFloat(y) + 0.5), artScale, 100 + CGFloat(y) * 10)
            solids.insert("\(x),\(y)"); wallNodes["\(x),\(y)"] = (n, kind, remaining)
        }
        for x in 0..<columns { try wall(x, 0, x % 5 == 0 ? "steel" : "brick"); try wall(x, rows - 1, x % 5 == 0 ? "steel" : "brick") }
        for y in 1..<(rows - 1) { try wall(0, y, y % 5 == 0 ? "steel" : "brick"); try wall(columns - 1, y, y % 5 == 0 ? "steel" : "brick") }
        for (y, ranges) in [(5, [12...18, 25...29, 36...40]), (11, [5...10, 18...22, 28...31]), (18, [8...13, 21...25, 35...40])] {
            for range in ranges {
                for x in range {
                    try wall(x, y, x == range.lowerBound ? "steel" : "brick", y == 11 && x == 21 ? 3 : 15)
                }
            }
        }
        for y in 7...10 { try wall(15, y) }
        for y in 13...16 { try wall(29, y) }
        for y in 22...25 { try wall(21, y); try wall(27, y) }
        for x in 22...26 { try wall(x, 25) }
        for (key, (node, kind, remaining)) in wallNodes {
            let xy = key.split(separator: ",").map { Int($0)! }
            var mask = 0
            for (bit, dx, dy) in [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0)]
            where wallNodes["\(xy[0] + dx),\(xy[1] + dy)"]?.1 == kind { mask |= bit }
            node.texture = try art.texture(String(format: "px_%@_joint_%02d_%02d", kind, mask, remaining))
        }

        let offsets = [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0), (16, 1, -1), (32, 1, 1), (64, -1, 1), (128, -1, -1)]
        func liquid(_ kind: String, _ cells: Set<String>) throws {
            for s in cells.sorted() {
                let xy = s.split(separator: ",").map { Int($0)! }
                let x = xy[0], y = xy[1]
                var mask = 0
                for (bit, dx, dy) in offsets where cells.contains("\(x + dx),\(y + dy)") { mask |= bit }
                for (diag, a, b) in [(16, 1, 2), (32, 2, 4), (64, 4, 8), (128, 8, 1)]
                where mask & a == 0 || mask & b == 0 { mask &= ~diag }
                let n = try sprite(art, String(format: "px_%@_%03d_0", kind, mask),
                                   point(CGFloat(x) + 0.5, CGFloat(y) + 0.5), artScale, 5)
                liquidSprites.append((n, kind, mask))
            }
        }
        var waters = Set<String>()
        for (ox, oy) in [(4, 5), (34, 10)] {
            for y in 0..<5 {
                for x in 0..<7 where !(x == 0 && (y == 0 || y == 4)) && !(x == 6 && y < 2) {
                    waters.insert("\(ox + x),\(oy + y)")
                }
            }
        }
        try liquid("water", waters)
        var ice = Set<String>()
        for y in 3...6 { for x in 40...44 { ice.insert("\(x),\(y)") } }
        try liquid("ice", ice)

        for i in 0..<115 {
            let x = 1 + (i * 17 + 3) % 46, y = 1 + (i * 11 + i / 8) % 25
            guard !solids.contains("\(x),\(y)"), !waters.contains("\(x),\(y)"), !(x > 39 && y < 7) else { continue }
            let name = i % 11 == 0 ? "flowers" : i % 4 == 0 ? "moss" : "pebbles"
            let n = try sprite(art, "px_prop_" + name, point(CGFloat(x) + 0.25, CGFloat(y) + 0.6),
                               artScale * (i % 4 == 0 ? 0.62 : 0.34), 6)
            n.alpha = name == "pebbles" ? 0.72 : 0.92
        }
        for (key, _) in wallNodes where !key.hasPrefix("0,") {
            let xy = key.split(separator: ",").map { Int($0)! }
            let x = xy[0], y = xy[1]
            if (x + y) % 5 == 0 && y < 25 && !solids.contains("\(x),\(y + 1)") {
                try sprite(art, "px_prop_moss", point(CGFloat(x) + 0.5, CGFloat(y) + 1.15), artScale * 0.5, 91 + CGFloat(y) * 10)
            }
        }
        for (i, xy) in [(3, 3), (12, 7), (18, 12), (33, 17), (40, 20), (6, 19), (30, 8), (44, 23), (17, 23)].enumerated() {
            try sprite(art, "px_prop_" + (i % 3 == 0 ? "bush_sparse" : "bush_dense"),
                       point(CGFloat(xy.0), CGFloat(xy.1)), artScale * 0.75, 90 + CGFloat(xy.1) * 10)
        }
        try sprite(art, "px_prop_lily", point(7, 7), artScale * 0.5, 10)
        try sprite(art, "px_prop_rocks", point(32, 22), artScale * 0.5, 100)
        try sprite(art, "px_prop_drain", point(42, 8), artScale * 0.55, 10)
        try sprite(art, "px_prop_bridge_ns", point(37, 10), artScale * 0.8, 20)
        for x: CGFloat in [9, 24, 38] { try sprite(art, "px_prop_spawn", point(x, 2.5), artScale * 0.6, 20) }

        let base = try PixelBaseNode(pixelScale: artScale * 0.82, art: art)
        base.position = point(24, 23.7); base.zPosition = 337
        addChild(base); baseNode = base
        try base.update(damageState: 0, shieldPhase: .active, age: 0)

        for spec in tankSpecs {
            let t = try PixelTankNode(kind: spec.kind, weapon: spec.weapon, direction: spec.dir,
                                      pixelScale: artScale * 0.82, art: art)
            t.position = point(spec.x, spec.y); t.zPosition = 100 + spec.y * 10
            addChild(t); tanks.append(t)
        }
        try tanks[6].setEquipment("moon")

        for (i, p) in [(16.0, 20.0), (33.0, 15.0), (6.0, 16.0), (31.0, 6.0)].enumerated() {
            try sprite(art, "px_mine_\(i)_armed", point(p.0, p.1), artScale * 0.65, 600)
        }
        for (id, x, y) in [(1, 17.0, 8.5), (21, 31.0, 18.0), (7, 11.0, 21.0)] {
            let p = try PixelPickupNode(id: id, pixelScale: artScale * 0.65, art: art)
            p.position = point(x, y); p.zPosition = 620
            addChild(p); pickups.append(p)
        }

        let fx = try PixelEffectNode(kind: .tankExplosion, pixelScale: artScale * 0.85, art: art)
        fx.position = point(26, 12.8); fx.zPosition = 670; addChild(fx); effects.append(fx)
        let wake = try PixelEffectNode(kind: .waterHit, pixelScale: artScale * 0.7, art: art)
        wake.position = point(35, 13); wake.zPosition = 670; addChild(wake); effects.append(wake)

        addChild(dynamicLayer)

        // Screen-space touch controls and HUD, exactly as the delivery fixture lays them out.
        let j = try sprite(art, "px_ui_joystick_normal", CGPoint(x: max(44, origin.x + 18), y: origin.y + 47), 1, 8000)
        j.size = CGSize(width: 76, height: 76); j.alpha = 0.6
        let knob = try sprite(art, "px_ui_control_knob", j.position, 1, 8100)
        knob.size = CGSize(width: 52, height: 52); knob.alpha = 0.82
        for (kind, p) in [("normal", CGPoint(x: arenaRect.maxX - 72, y: origin.y + 40)),
                          ("fire", CGPoint(x: min(size.width - 38, arenaRect.maxX - 11), y: origin.y + 83))] {
            let button = try sprite(art, "px_ui_control_" + (kind == "normal" ? "normal" : "special"), p, 1, 8000)
            button.size = CGSize(width: 62, height: 62); button.alpha = 0.84
            let icon = try sprite(art, kind == "normal" ? "px_projectile_normal" : art.manifest.pickups[21].texture, p, 1, 8100)
            icon.size = CGSize(width: kind == "normal" ? 74 : 36, height: kind == "normal" ? 74 : 36)
            icon.zRotation = kind == "normal" ? -.pi / 4 : 0
        }
        let hudY = arenaRect.maxY + 1
        let panel = try sprite(art, "px_ui_panel_normal", CGPoint(x: origin.x + 4 + (size.width - 8) / 2, y: hudY + 11), 1, 8900)
        panel.size = CGSize(width: width - 8, height: 22)
        panel.centerRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        label("♥ 3   ARMOR 6/8", origin.x + 91, hudY + 7, 10)
        label("01 · FRONTIER", size.width / 2, hudY + 7, 11)
        label("BASE 85   ENEMY 18", arenaRect.maxX - 95, hudY + 7, 10)
    }

    private func tickArena(_ art: PixelArt, phase: Int, animationTime: Double) throws {
        let framePhase = phase % 4
        for (node, kind, mask) in liquidSprites {
            node.texture = try art.texture(String(format: "px_%@_%03d_%d", kind, mask, framePhase))
        }
        for t in tanks { try t.setTreadPhase(phase) }

        // Player tank drives a square patrol leg exactly like the delivery's battle mode.
        let player = tanks[0]
        let leg = (phase / 6) % 4, u = CGFloat(phase % 6) / 6
        try player.setDirection([0, 3, 2, 1][leg])
        let tx: CGFloat = [19, 19 - 2 * u, 17, 17 + 2 * u][leg]
        let ty: CGFloat = [22 - 2 * u, 20, 20 + 2 * u, 22][leg]
        player.position = point(tx, ty)
        player.setRecoil(CGFloat(framePhase) / 3)

        dynamicLayer.removeAllChildren()
        let dx: [CGFloat] = [0, 1, 0, -1], dy: [CGFloat] = [1, 0, -1, 0]
        for i in [0, 3, 4] {
            let t = tanks[i], weapon = tankSpecs[i].weapon, dir = t.direction
            let effectName = weapon == "normal" ? "muzzle" : weapon
            if let frames = art.manifest.effects[effectName] {
                let flash = try sprite(art, frames[framePhase], t.muzzle(in: self), artScale * 0.48, 650, in: dynamicLayer)
                flash.zRotation = -CGFloat(dir) * .pi / 2
            }
            for step in 1...2 {
                let p = t.muzzle(in: self), id = "px_projectile_" + weapon
                let travel = CGFloat(step) * 1.4 + CGFloat(framePhase) * 0.24
                let bullet = try sprite(art, id, CGPoint(x: p.x + dx[dir] * cell * travel, y: p.y + dy[dir] * cell * travel),
                                        artScale * 0.8, 660, in: dynamicLayer)
                if let bounds = art.manifest.sprites[id]?.contentBounds {
                    let rawWidth = (bounds[2] - bounds[0]) * artScale * 0.8
                    let minWidth: CGFloat = weapon == "normal" ? 1.8 : 2.2
                    bullet.xScale = max(1, min(4, minWidth / rawWidth))
                }
                bullet.zRotation = -CGFloat(dir) * .pi / 2
            }
        }
        for p in pickups { try p.update(phase: .idle, age: animationTime) }
        for fx in effects { try fx.advance(to: animationTime.truncatingRemainder(dividingBy: 1.5)) }
        try baseNode?.update(damageState: 0, shieldPhase: .active, age: animationTime)
    }

    // MARK: - Roster and directions fixtures

    private func buildRoster(_ art: PixelArt) throws {
        let kinds = ["player", "scout", "standard", "armored", "heavy"]
        let weapons = ["normal", "rapid", "fire", "ap", "explosion", "mine"]
        for (r, kind) in kinds.enumerated() {
            for (c, weapon) in weapons.enumerated() {
                let t = try PixelTankNode(kind: kind, weapon: weapon, direction: 0, pixelScale: 1.65, art: art)
                t.position = CGPoint(x: CGFloat(c + 1) * size.width / 7,
                                     y: size.height - 48 - CGFloat(r) * (size.height - 65) / 5)
                addChild(t); tanks.append(t)
                label(kind + " " + weapon, t.position.x, t.position.y - 31, 8)
            }
        }
    }

    private func buildDirections(_ art: PixelArt) throws {
        for row in 0..<3 {
            for dir in 0..<4 {
                let t = try PixelTankNode(kind: row == 0 ? "player" : "standard",
                                          weapon: row == 2 ? "fire" : "normal",
                                          direction: dir, pixelScale: 2, art: art)
                t.position = CGPoint(x: CGFloat(dir + 1) * size.width / 5, y: size.height - 65 - CGFloat(row) * 105)
                addChild(t); tanks.append(t)
                label(PixelTankNode.directions[dir], t.position.x, t.position.y - 43, 10)
            }
        }
        label("equipment: amphi / anti_skid / moon / memory", size.width / 2, 10, 10)
        for (i, equipment) in ["amphi", "anti_skid", "moon", "memory"].enumerated() {
            let t = try PixelTankNode(kind: "player", weapon: "normal", direction: 1, pixelScale: 1.4, art: art)
            t.position = CGPoint(x: CGFloat(i + 1) * size.width / 5, y: 48)
            try t.setEquipment(equipment)
            addChild(t); tanks.append(t)
        }
    }

    // MARK: - Item sheet (pickups, mines, base states, effects)

    private func buildItems(_ art: PixelArt) throws {
        label("PICKUPS 0–24", size.width / 2, size.height - 22, 10)
        for item in art.manifest.pickups {
            let p = try PixelPickupNode(id: item.id, pixelScale: 1.05, art: art)
            let column = item.id % 13, row = item.id / 13
            p.position = CGPoint(x: CGFloat(column + 1) * size.width / 14,
                                 y: size.height - 62 - CGFloat(row) * 52)
            addChild(p); pickups.append(p)
        }
        label("MINES L0–L3 · player/enemy", size.width / 2, size.height - 172, 10)
        for level in 0...3 {
            for (o, owner) in ["player", "enemy"].enumerated() {
                let m = try PixelMineNode(level: level, owner: owner, surface: .ground, pixelScale: 1.15, art: art)
                m.position = CGPoint(x: size.width * (0.2 + CGFloat(level * 2 + o) * 0.086), y: size.height - 205)
                addChild(m)
                try m.update(phase: .armed, age: 0, progress: 1)
            }
        }
        label("BASE states + shield", size.width * 0.25, size.height - 250, 10)
        for state in 0...3 {
            let b = try PixelBaseNode(pixelScale: 0.95, art: art)
            b.position = CGPoint(x: size.width * (0.1 + CGFloat(state) * 0.1), y: size.height - 300)
            addChild(b)
            try b.update(damageState: state, shieldPhase: state == 0 ? .active : .absent, age: 0)
        }
        label("EFFECTS", size.width * 0.72, size.height - 250, 10)
        let kinds: [PixelEffectKind] = [.tankExplosion, .groundExplosion, .fireBurn, .freezeBurst, .waterHit, .pickupCollect]
        for (i, kind) in kinds.enumerated() {
            let fx = try PixelEffectNode(kind: kind, pixelScale: 1.3, art: art)
            fx.position = CGPoint(x: size.width * (0.52 + CGFloat(i % 3) * 0.16),
                                  y: size.height - 300 - CGFloat(i / 3) * 55)
            addChild(fx); effects.append(fx)
        }
    }

    // MARK: - Presentation clock

    override func update(_ currentTime: TimeInterval) {
        guard let art else { return }
        let start = startTime ?? currentTime
        startTime = start
        let newPhase = Int((currentTime - start) * 12)
        guard newPhase != phase else { return }
        phase = newPhase
        let animationTime = Double(phase) / 12
        do {
            switch mode {
            case .battle:
                try tickArena(art, phase: phase, animationTime: animationTime)
            case .roster:
                let dir = (phase / 24) % 4
                if dir != rosterDirection {
                    rosterDirection = dir
                    for t in tanks { try t.setDirection(dir) }
                }
                for t in tanks { try t.setTreadPhase(phase) }
            case .directions:
                for t in tanks { try t.setTreadPhase(phase) }
            case .items:
                for p in pickups { try p.update(phase: .idle, age: animationTime) }
                for fx in effects {
                    let cycle = fx.loops ? animationTime : animationTime.truncatingRemainder(dividingBy: max(fx.duration, 0.9))
                    try fx.advance(to: cycle)
                }
            }
        } catch {
            // Art tick failures are presentation-only; freeze rather than crash the fixture.
        }
    }
}
