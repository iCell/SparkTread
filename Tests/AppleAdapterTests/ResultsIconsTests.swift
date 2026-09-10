import CoreGraphics
import Foundation
import Testing
import GameCore
@testable import AppleAdapters

/// ADR-0012 (owner: tank icons in the results table): one icon per reward
/// category, composed from the rig sprites the scene itself uses.
@Suite @MainActor struct ResultsIconsTests {
    private func loadArt() throws -> PixelArt {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/SparkTreadPixel")
        return try PixelArt(root: root)
    }

    @Test func everyCategoryRendersAnOpaqueBodySizedIcon() throws {
        let art = try loadArt()
        for category in 0..<ScoreRules.rewardCategoryCount {
            let image = try PixelTankIcons.image(category: category, art: art)
            #expect(image.width == 32 && image.height == 26, "category \(category)")
            let data = try #require(image.dataProvider?.data as Data?)
            var opaque = 0
            for i in stride(from: 3, to: data.count, by: 4) where data[i] > 200 { opaque += 1 }
            #expect(opaque > 200, "category \(category) icon is mostly transparent (\(opaque) opaque px)")
        }
        #expect(throws: PixelArtError.self) { try PixelTankIcons.image(category: 8, art: art) }
    }

    @Test func categoriesShowTheirFamilyAndTier() {
        let looks = PixelTankIcons.archetypes.map { PixelTankNode.appearance(archetypeID: $0, isPlayer: false) }
        #expect(looks.map(\.weapon) == ["normal", "normal", "rapid", "mine", "explosion", "fire", "ap", "ap"])
        #expect(looks.map(\.kind) == ["scout", "armored", "scout", "scout", "scout", "scout", "scout", "armored"])
        // The scene's mapping, unchanged: tier letter → chassis, family → turret.
        #expect(PixelTankNode.appearance(archetypeID: "normal_b", isPlayer: false) == ("standard", "normal"))
        #expect(PixelTankNode.appearance(archetypeID: "fire_d", isPlayer: false) == ("heavy", "fire"))
        #expect(PixelTankNode.appearance(archetypeID: "dragon_z", isPlayer: false) == ("scout", "normal"))
        #expect(PixelTankNode.appearance(archetypeID: "anything", isPlayer: true) == ("player", "normal"))
    }
}
