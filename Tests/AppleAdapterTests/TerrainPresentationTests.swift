import Foundation
import SpriteKit
import Testing
import GameCore
@testable import AppleAdapters

@Suite @MainActor struct TerrainPresentationTests {
    private func makeScene() throws -> (PixelArt, MovementLabScene, WorldState) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/SparkTreadPixel")
        let art = try PixelArt(root: root)
        let world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 1)
        let scene = MovementLabScene(size: CGSize(width: 844, height: 390),
                                     controller: MovementLabController(world: world))
        return (art, scene, world)
    }

    @Test func destroyedWallCanBeRebuiltAndChangeMaterial() throws {
        var (art, scene, world) = try makeScene()
        world.terrain[10, 10] = TerrainCell(kind: .brick)
        scene.refreshWallTexture(art, world: world, cellX: 10, cellY: 10)
        #expect(scene.children.count == 1)
        #expect((scene.children.first as? SKSpriteNode)?.texture ===
                (try art.texture("px_brick_joint_00_15")))

        world.terrain[10, 10] = TerrainCell(kind: .ground)
        scene.refreshWallTexture(art, world: world, cellX: 10, cellY: 10)
        #expect(scene.children.isEmpty)

        world.terrain[10, 10] = TerrainCell(kind: .steel)
        scene.refreshWallTexture(art, world: world, cellX: 10, cellY: 10)
        #expect(scene.children.count == 1)
        #expect((scene.children.first as? SKSpriteNode)?.texture ===
                (try art.texture("px_steel_joint_00_15")))

        world.terrain[10, 10] = TerrainCell(kind: .brick)
        scene.refreshWallTexture(art, world: world, cellX: 10, cellY: 10)
        #expect(scene.children.count == 1)
        #expect((scene.children.first as? SKSpriteNode)?.texture ===
                (try art.texture("px_brick_joint_00_15")))
    }

    /// Round-2 obligation: terrain reconciliation runs in both directions —
    /// water hardened to steel loses its liquid tile, and water restored
    /// after the shield gets it back (authority and rendering agree).
    @Test func liquidsAreReconciledThroughHardeningAndRestoration() throws {
        var (art, scene, world) = try makeScene()
        world.terrain[12, 12] = TerrainCell(kind: .water)
        scene.reconcileTerrainCell(art, world: world, cellX: 12, cellY: 12)
        #expect(scene.children.count == 1)
        #expect(scene.children.first?.name == "px_water_000_0")

        world.terrain[12, 12] = TerrainCell(kind: .steel)
        scene.reconcileTerrainCell(art, world: world, cellX: 12, cellY: 12)
        #expect(scene.children.count == 1)
        #expect((scene.children.first as? SKSpriteNode)?.texture ===
                (try art.texture("px_steel_joint_00_15")))

        world.terrain[12, 12] = TerrainCell(kind: .water)
        scene.reconcileTerrainCell(art, world: world, cellX: 12, cellY: 12)
        #expect(scene.children.count == 1)
        #expect(scene.children.first?.name == "px_water_000_0")

        world.terrain[12, 12] = TerrainCell(kind: .ice)
        scene.reconcileTerrainCell(art, world: world, cellX: 12, cellY: 12)
        #expect(scene.children.count == 1)
        #expect(scene.children.first?.name == "px_ice_000_0")
    }

    /// ADR-0016: foliage is drawn above tanks (below mines/projectiles),
    /// jointed to its neighbours, and fades where it covers the player.
    @Test func foliageOverlaysTanksAndFadesOverThePlayer() throws {
        var (art, scene, world) = try makeScene()
        for y in 9...11 { for x in 9...11 { world.terrain[x, y] = TerrainCell(kind: .foliage) } }
        let cell = SpatialUnits.subunitsPerCell
        world.addPlayer(PlayerState(playerID: .one))
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 9 * cell, y: 9 * cell), facing: .up)
        scene.installForTests(art: art, world: world)
        for y in 9...11 { for x in 9...11 { scene.reconcileTerrainCell(art, world: world, cellX: x, cellY: y) } }
        scene.syncForTests(world: world) // the per-frame pass joints and fades
        let centre = try #require(scene.foliageNodeForTests(cellX: 10, cellY: 10, world: world))
        #expect(centre.zPosition == MovementLabScene.foliageZPosition)
        #expect(MovementLabScene.foliageZPosition > 500 && MovementLabScene.foliageZPosition < 600) // tanks < foliage < mines
        #expect(centre.texture === (try art.texture("px_foliage_255_0"))) // fully surrounded joint, frame 0
        let corner = try #require(scene.foliageNodeForTests(cellX: 9, cellY: 9, world: world))
        #expect(corner.texture === (try art.texture("px_foliage_038_0"))) // right + down + the diagonal between
        // The player's 2×2 footprint covers cells 9–10 × 9–10: those fade, the
        // rest stay opaque (SpriteKit stores alpha as Float: compare loosely).
        func faded(_ node: SKSpriteNode) -> Bool { abs(node.alpha - MovementLabScene.foliageFadedAlpha) < 0.001 }
        #expect(faded(corner) && faded(centre))
        let far = try #require(scene.foliageNodeForTests(cellX: 11, cellY: 11, world: world))
        #expect(abs(far.alpha - 1) < 0.001)
        // Foliage removed from the world disappears from the scene.
        world.terrain[10, 10] = TerrainCell(kind: .ground)
        scene.reconcileTerrainCell(art, world: world, cellX: 10, cellY: 10)
        #expect(scene.foliageNodeForTests(cellX: 10, cellY: 10, world: world) == nil)
        scene.syncForTests(world: world)
        #expect(scene.foliageNodeForTests(cellX: 9, cellY: 9, world: world)?.texture === (try art.texture("px_foliage_006_0")))
    }

    @Test func equipmentIDsMapToDeliveryAttachmentNames() {
        #expect(MovementLabScene.equipmentArtName("amphi_tank") == "amphi")
        #expect(MovementLabScene.equipmentArtName("anti_skid") == "anti_skid")
        #expect(MovementLabScene.equipmentArtName("shield_of_moon") == "moon")
        #expect(MovementLabScene.equipmentArtName("memory_of_sea") == "memory")
        #expect(MovementLabScene.equipmentArtName(nil) == nil)
    }

    /// Owner report 2026-09-10: the moon plow sat on the tank's flank. The
    /// atlas draws it on the right for every facing, so the right-facing
    /// sprite is rotated to the front; the other attachments keep their
    /// per-facing sprites.
    @Test func theMoonPlowTurnsToTheTankFront() throws {
        let (art, _, _) = try makeScene()
        let rightSprite = try art.texture("px_equipment_moon_right")
        for (direction, rotation) in [(0, CGFloat.pi / 2), (1, 0), (2, -CGFloat.pi / 2), (3, CGFloat.pi)] {
            let node = try PixelTankNode(kind: "scout", weapon: "normal", direction: direction, pixelScale: 1, art: art)
            try node.setEquipment("moon")
            let plow = try #require(node.children.first { $0.zPosition == 4 } as? SKSpriteNode)
            #expect(plow.texture === rightSprite && abs(plow.zRotation - rotation) < 0.001, "direction \(direction)")
            #expect(PixelTankNode.frontRotation(direction) == rotation)
        }
        let skirt = try PixelTankNode(kind: "scout", weapon: "normal", direction: 0, pixelScale: 1, art: art)
        try skirt.setEquipment("anti_skid")
        let attachment = try #require(skirt.children.first { $0.zPosition == 0 } as? SKSpriteNode)
        #expect(attachment.texture === (try art.texture("px_equipment_anti_skid_up")) && attachment.zRotation == 0)
    }

    /// R5-03: the own-fire base cue tints an actual overlay sprite (teal for
    /// allied, red for enemy), not the vendor node.
    @Test func baseFlashTintsAnOverlaySprite() throws {
        var (art, scene, world) = try makeScene()
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
        scene.installForTests(art: art, world: world)
        scene.flashBase(art, allied: true, damageState: 0)
        let allied = try #require(scene.baseFlash)
        #expect(allied.parent === scene)
        #expect(allied.colorBlendFactor > 0.5)
        #expect(allied.name == "base_flash_allied")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        allied.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(g > 0.8 && r < 0.3) // teal
        scene.flashBase(art, allied: false, damageState: 1)
        let enemy = try #require(scene.baseFlash)
        #expect(enemy !== allied && allied.parent == nil) // one overlay at a time
        enemy.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.9 && g < 0.3) // red
        #expect(enemy.name == "base_flash_enemy")
    }

    /// R5-04: a muzzle flash is anchored to the event's position and facing;
    /// a shooter that moved (same facing) does not drag the flash along.
    @Test func muzzleFlashIsAnchoredToTheEventNotTheLiveNode() throws {
        var (art, scene, world) = try makeScene()
        let id = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                 positionSubunits: Vec2i(x: 10 * 1024, y: 10 * 1024), facing: .right)
        scene.installForTests(art: art, world: world)
        let firedAt = Vec2i(x: 10 * 1024, y: 10 * 1024)
        let anchored = scene.muzzleScenePoint(entityID: id, position: firedAt, facing: .right)
        // The shooter rolls on with the same facing; the scene mirrors it.
        world.withTank(entityID: id) { $0.positionSubunits = Vec2i(x: 14 * 1024, y: 10 * 1024) }
        scene.syncForTests(world: world)
        let afterMove = scene.muzzleScenePoint(entityID: id, position: firedAt, facing: .right)
        #expect(afterMove == anchored)
        // A turned shooter (or a dead one) falls back to the geometric muzzle.
        let geometric = scene.muzzleScenePoint(entityID: id, position: firedAt, facing: .up)
        let gone = scene.muzzleScenePoint(entityID: 999, position: firedAt, facing: .up)
        #expect(geometric == gone)
        // The rig offset points along the facing: right of the anchor.
        let center = scene.muzzleScenePoint(entityID: 999, position: firedAt, facing: .right)
        #expect(anchored.x > center.x - 1)
    }
}
