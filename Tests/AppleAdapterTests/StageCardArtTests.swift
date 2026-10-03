import CoreGraphics
import Foundation
import Testing
import GameApplication
@testable import AppleAdapters

/// The select screen draws each stage's own map as its background, so the
/// card art is only as right as the preview under it.
@Suite @MainActor struct StageCardArtTests {
    private func contentRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func everyCampaignStageRendersItsOwnMap() throws {
        let root = contentRoot()
        let campaign = try CampaignLoader.load(at: root.appendingPathComponent("Content/campaigns/campaign_v1.json"))
        var seen = Set<String>()
        for id in campaign.stageIDs {
            let def = try StageLoader.loadDefinition(at: root.appendingPathComponent("Content/stages/\(id).json"))
            let map = StagePreview.map(of: def)
            #expect(map.width == 56 && map.height == 27, "\(id)")
            // The three markers are what make a card readable as a place:
            // where they come from, where you start, what you defend.
            #expect(map.cells.contains(.enemySpawn), "\(id) has no enemy spawn marker")
            #expect(map.cells.contains(.playerSpawn), "\(id) has no player spawn marker")
            #expect(map.cells.contains(.base), "\(id) has no base marker")
            // The base sits where the stage puts it, not where a flip left it.
            #expect(map[def.baseSpawn[0], def.baseSpawn[1]] == .base, "\(id) base marker misplaced")
            let image = try #require(StageCardArt.image(for: map, id: id), "\(id) produced no card art")
            #expect(image.width == 56 && image.height == 27, "\(id)")
            // Twelve identical cards would defeat the point of having art.
            seen.insert(map.cells.map { String($0.rawValue) }.joined())
        }
        #expect(seen.count == campaign.stageIDs.count, "two stages render the same card")
    }

    /// Every theme a stage may declare has to reach a distinct ground
    /// colour, or the four themes stop being worth carrying.
    @Test func themesRenderDistinctGround() throws {
        let root = contentRoot()
        let campaign = try CampaignLoader.load(at: root.appendingPathComponent("Content/campaigns/campaign_v1.json"))
        var groundByTheme: [String: [UInt8]] = [:]
        for id in campaign.stageIDs {
            let def = try StageLoader.loadDefinition(at: root.appendingPathComponent("Content/stages/\(id).json"))
            let image = try #require(StageCardArt.image(for: StagePreview.map(of: def), id: id))
            // Cell (1, 3) is open ground on every stage: the row kept clear
            // across the map so no spawn can be walled in.
            groundByTheme[def.themeID] = pixel(image, x: 1, y: 3)
        }
        #expect(groundByTheme.count == 4, "the campaign should cover all four themes")
        #expect(Set(groundByTheme.values.map { "\($0)" }).count == groundByTheme.count,
                "two themes share a ground colour: \(groundByTheme)")
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let at = (y * image.width + x) * 4
        return Array(bytes[at..<(at + 3)])
    }

    /// Every campaign stage must resolve to its own number and a Chinese
    /// name. The id is <theme>_<NN>_<name> and the theme is not always one
    /// word — `iron_citadel_08_…` broke a parser that read the number out of
    /// position 1, so four stages showed "STAGE" with the number stranded in
    /// the subtitle (2026-10-03).
    @Test func everyStageResolvesANumberAndAChineseName() throws {
        let root = contentRoot()
        let campaign = try CampaignLoader.load(at: root.appendingPathComponent("Content/campaigns/campaign_v1.json"))
        for (index, id) in campaign.stageIDs.enumerated() {
            let card = HUDLabels.stageCard(id)
            #expect(card.title == String(format: "STAGE %02d", index + 1), "\(id) titled '\(card.title)'")
            #expect(!card.subtitle.isEmpty, "\(id) has no subtitle")
            // A fallback subtitle is the id spelled out in Latin letters;
            // a named stage is not.
            #expect(card.subtitle.allSatisfy { !$0.isASCII }, "\(id) fell back to '\(card.subtitle)'")
        }
    }
}
