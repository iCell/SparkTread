import SpriteKit

/// Diagnostic smoke-test scene for the pixel art pipeline.
///
/// It answers one question that cannot be answered without Xcode: did the `.atlas` folders
/// compile into `.atlasc`, did `pixel_assets.json` land in the bundle, and does
/// `PixelTankNode` assemble hull, treads, and turret with the manifest's anchors? It draws
/// four player tanks — one per weapon, one per facing — and nothing else.
///
/// This scene holds no gameplay state and is replaced by the real arena scene in M1.
final class BootstrapScene: SKScene {

    /// Weapon and facing pairs to display, left to right.
    private static let samples: [(weapon: String, direction: Int)] = [
        ("normal", 0), // up
        ("rapid", 1),  // right
        ("fire", 2),   // down
        ("ap", 3),     // left
    ]

    /// Sprite magnification. Manifest art is authored at 16 logical pixels per cell, so a
    /// whole-number scale keeps pixels square and crisp.
    private static let pixelScale: CGFloat = 4

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        removeAllChildren()

        addChild(makeLabel(
            text: "SparkTread bootstrap",
            position: CGPoint(x: size.width / 2, y: size.height * 0.78),
            fontSize: 28
        ))

        do {
            let art = try PixelArt()
            try addTanks(using: art)
        } catch {
            // A diagnostic scene must show the failure, not swallow it: a blank screen
            // would look identical to a bundle that simply shipped no art.
            addChild(makeLabel(
                text: "PixelArt failed: \(error)",
                position: CGPoint(x: size.width / 2, y: size.height * 0.5),
                fontSize: 18
            ))
        }
    }

    /// Lays the sample tanks out in an evenly spaced row across the middle of the scene.
    private func addTanks(using art: PixelArt) throws {
        let samples = Self.samples
        let spacing = size.width / CGFloat(samples.count + 1)

        for (index, sample) in samples.enumerated() {
            let tank = try PixelTankNode(
                kind: "player",
                weapon: sample.weapon,
                direction: sample.direction,
                pixelScale: Self.pixelScale,
                art: art
            )
            // Stagger the tread phase so a static screenshot still shows all four frames.
            try tank.setTreadPhase(index)
            tank.position = CGPoint(x: spacing * CGFloat(index + 1), y: size.height * 0.5)
            addChild(tank)

            addChild(makeLabel(
                text: sample.weapon,
                position: CGPoint(x: tank.position.x, y: size.height * 0.30),
                fontSize: 18
            ))
        }
    }

    /// Builds a centered monospaced label; the pixel art has no font of its own yet.
    private func makeLabel(text: String, position: CGPoint, fontSize: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = fontSize
        label.fontColor = SKColor(white: 0.85, alpha: 1)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = position
        label.zPosition = 100
        return label
    }
}
