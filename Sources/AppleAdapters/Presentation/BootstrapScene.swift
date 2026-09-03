import SpriteKit
import GameApplication
import GameCore

/// M0 bootstrap scene: renders the empty universal arena so the uniform
/// full-map fit (ADR-0004) is visible on device. Debug visuals only — real
/// terrain rendering uses composited chunk textures from M1 onward.
public final class BootstrapScene: SKScene {
    /// Presentation scale for the bootstrap scene only; authoritative
    /// positions are subunits (ADR-0001) and never depend on this value.
    private static let pointsPerCell: CGFloat = 40

    private let session: BootstrapSession

    public init(session: BootstrapSession) {
        self.session = session
        let arena = session.arena
        super.init(size: CGSize(
            width: CGFloat(arena.cellsWide) * Self.pointsPerCell,
            height: CGFloat(arena.cellsHigh) * Self.pointsPerCell
        ))
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("BootstrapScene is created by the composition root")
    }

    override public func didMove(to view: SKView) {
        removeAllChildren()
        addChild(makeArenaFloor())
        addChild(makeCellGrid())
        addChild(makeTankFootprintMarker())
        addChild(makeCaption())
    }

    private func makeArenaFloor() -> SKNode {
        let floor = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
            size: size
        )
        floor.anchorPoint = .zero
        return floor
    }

    private func makeCellGrid() -> SKNode {
        let path = CGMutablePath()
        let arena = session.arena
        for x in 0...arena.cellsWide {
            let px = CGFloat(x) * Self.pointsPerCell
            path.move(to: CGPoint(x: px, y: 0))
            path.addLine(to: CGPoint(x: px, y: size.height))
        }
        for y in 0...arena.cellsHigh {
            let py = CGFloat(y) * Self.pointsPerCell
            path.move(to: CGPoint(x: 0, y: py))
            path.addLine(to: CGPoint(x: size.width, y: py))
        }
        let grid = SKShapeNode(path: path)
        grid.strokeColor = SKColor(white: 1, alpha: 0.08)
        grid.lineWidth = 1
        return grid
    }

    private func makeTankFootprintMarker() -> SKNode {
        let cells = CGFloat(SpatialUnits.standardTankFootprintSubunits)
            / CGFloat(SpatialUnits.subunitsPerCell)
        let edge = cells * Self.pointsPerCell
        let marker = SKSpriteNode(
            color: SKColor(red: 0.95, green: 0.72, blue: 0.20, alpha: 1),
            size: CGSize(width: edge, height: edge)
        )
        marker.position = CGPoint(x: size.width / 2, y: size.height / 2)
        return marker
    }

    private func makeCaption() -> SKNode {
        let arena = session.arena
        let caption = SKLabelNode(fontNamed: "Menlo-Bold")
        caption.text = "M0 BOOTSTRAP · ARENA \(arena.cellsWide)×\(arena.cellsHigh) · UNIFORM FIT"
        caption.fontSize = 28
        caption.fontColor = SKColor(white: 1, alpha: 0.85)
        caption.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        return caption
    }
}
