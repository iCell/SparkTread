import CoreGraphics
import SwiftUI

/// The menus' backdrop (owner 2026-10-03: the title and select screens were
/// bare text on black and "显得很单调").
///
/// It is built from the game's own material rather than a separate set of
/// menu art: the steel plate the arena's walls are made of, tiled and taken
/// right down, under the same top light and vignette the playfield reads
/// with. So the menus sit inside the fortress the battles happen in, the
/// look cannot drift from the game's, and nothing new is bundled — the tile
/// is one sprite already in the atlas, upscaled by whole pixels so it stays
/// pixel art.
@MainActor enum MenuArt {
    private static var cache: [String: CGImage] = [:]
    private static var art: PixelArt? = {
        try? PixelArt()
    }()


    /// The player's own tank facing right, composed and cropped to its body
    /// — the intro's own element. It works here where a watermark did not,
    /// because it MOVES: a top-down tank is a rectangle standing still and a
    /// tank once it drives.
    static var playerTank: CGImage? {
        if let cached = cache["tank"] { return cached }
        guard let art, let image = try? PixelTankIcons.image(kind: "player", weapon: "normal",
                                                             facing: "right", art: art)
        else { return nil }
        cache["tank"] = image
        return image
    }

    /// The right-facing player rig's muzzle in the cropped icon's own
    /// pixels (origin top-left), so the intro's shells leave the gun
    /// wherever and however large the icon is drawn — the manifest's muzzle
    /// point, not a number read off a screenshot.
    static var playerTankMuzzle: CGPoint? {
        guard let art, let rig = art.manifest.rigs["player_right"],
              let turret = art.manifest.turrets["player_normal_right"],
              let muzzle = turret.muzzles.first, muzzle.count == 2, rig.bodyBounds.count == 4
        else { return nil }
        return CGPoint(x: muzzle[0] - rig.bodyBounds[0], y: muzzle[1] - rig.bodyBounds[1])
    }

    /// One sprite as the atlas holds it, by id — the intro's shell and
    /// muzzle flash are the scene's own, at the scene's own proportions.
    static func sprite(_ id: String) -> CGImage? {
        if let cached = cache[id] { return cached }
        guard let image = try? art?.texture(id).cgImage() else { return nil }
        cache[id] = image
        return image
    }

    /// A sprite's anchor as a unit point of its canvas — for an effect
    /// frame, the point that sits on the muzzle.
    static func anchor(of id: String) -> UnitPoint? {
        guard let spec = art?.manifest.sprites[id], spec.anchorTopLeft.count == 2,
              spec.pixelSize.count == 2, spec.pixelSize[0] > 0, spec.pixelSize[1] > 0 else { return nil }
        return UnitPoint(x: spec.anchorTopLeft[0] / spec.pixelSize[0],
                         y: spec.anchorTopLeft[1] / spec.pixelSize[1])
    }

    /// A sprite upscaled by a whole factor with no interpolation, so a
    /// 16 px plate tiles as 16 blocks and not as a blur.
    static func upscaled(_ id: String, by factor: Int) -> CGImage? {
        let key = "\(id)@\(factor)"
        if let cached = cache[key] { return cached }
        guard let source = try? art?.texture(id).cgImage() else { return nil }
        let width = source.width * factor, height = source.height * factor
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        cache[key] = image
        return image
    }
}

struct MenuBackdrop: View {
    // A tank watermark was tried and dropped (2026-10-03): a top-down tank
    // is a rectangle, so dimming it reads as a smudge and stencilling its
    // alpha reads as a block. The plate carries the screen on its own.
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.042, blue: 0.05)
            if let plate = MenuArt.upscaled("px_steel_joint_15_15", by: 4) {
                Image(decorative: plate, scale: 1)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .opacity(0.3)
                    .blendMode(.plusLighter)
            }
            // Lit from the top like the plates themselves, dark at the edges,
            // so the yellow the menus accent with has somewhere to sit.
            LinearGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 180, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}
