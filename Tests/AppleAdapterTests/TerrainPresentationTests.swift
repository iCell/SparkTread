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

    @Test func equipmentIDsMapToDeliveryAttachmentNames() {
        #expect(MovementLabScene.equipmentArtName("amphi_tank") == "amphi")
        #expect(MovementLabScene.equipmentArtName("anti_skid") == "anti_skid")
        #expect(MovementLabScene.equipmentArtName("shield_of_moon") == "moon")
        #expect(MovementLabScene.equipmentArtName("memory_of_sea") == "memory")
        #expect(MovementLabScene.equipmentArtName(nil) == nil)
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
