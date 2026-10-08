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

    /// A sprite cropped to its drawn content (the manifest's contentBounds),
    /// for the HUD: a pickup is 22 px of art on a 32 px canvas, and an
    /// icon row set by canvas would be mostly padding.
    static func glyph(_ id: String) -> CGImage? {
        let key = "glyph:" + id
        if let cached = cache[key] { return cached }
        guard let full = sprite(id) else { return nil }
        guard let b = art?.manifest.sprites[id]?.contentBounds, b.count == 4,
              let cropped = full.cropping(to: CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]))
        else { return full }
        cache[key] = cropped
        return cropped
    }

    /// A tank composed from its rig, cropped to its body — the HUD's lives
    /// and enemy counters wear the same tanks the field does.
    static func tankIcon(kind: String, weapon: String = "normal", facing: String = "up") -> CGImage? {
        let key = "tank:\(kind):\(weapon):\(facing)"
        if let cached = cache[key] { return cached }
        guard let art, let image = try? PixelTankIcons.image(kind: kind, weapon: weapon, facing: facing, art: art)
        else { return nil }
        cache[key] = image
        return image
    }

    /// An enemy archetype's tank, through the same appearance mapping the
    /// field and the results table use (rigs are keyed by kind, not by
    /// archetype).
    static func tankIcon(archetypeID: String) -> CGImage? {
        let key = "tank:archetype:" + archetypeID
        if let cached = cache[key] { return cached }
        guard let art, let image = try? PixelTankIcons.image(archetypeID: archetypeID, art: art) else { return nil }
        cache[key] = image
        return image
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

    /// The backdrop is composed on a FIXED field centred on the screen, not
    /// stretched to it, because the launch screen is a render of that same
    /// field (owner 2026-10-06: the page before the title should flow into
    /// the intro, not be a black card). iOS centres a launch image at its
    /// intrinsic size and runs no code, so the only way the static page and
    /// the live view can agree to the pixel — plate grid, light, vignette —
    /// is for both to be the same picture anchored at the same point. The
    /// field covers every iPhone (956×440 pt at most); iPad would need a
    /// larger one.
    static let fieldSize = CGSize(width: 1024, height: 512)
    static let base = Color(red: 0.035, green: 0.042, blue: 0.05)

    var body: some View {
        ZStack {
            Self.base
            Field()
        }
        .clipped()
        .ignoresSafeArea()
    }

    /// The picture itself: what `launch-screen-renderer` bakes into the
    /// launch image, and what the title shows once the app runs.
    struct Field: View {
        var body: some View {
            ZStack {
                MenuBackdrop.base
                if let plate = MenuArt.upscaled("px_steel_joint_15_15", by: 4) {
                    Image(decorative: plate, scale: 1)
                        .resizable(resizingMode: .tile)
                        .interpolation(.none)
                        .opacity(0.3)
                        .blendMode(.plusLighter)
                }
                // Lit from the top like the plates themselves, dark at the
                // edges, so the yellow the menus accent with has somewhere
                // to sit.
                LinearGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.clear, .black.opacity(0.55)],
                               center: .center, startRadius: 180, endRadius: 620)
            }
            .frame(width: MenuBackdrop.fieldSize.width, height: MenuBackdrop.fieldSize.height)
        }
    }
}

/// The launch image: `MenuBackdrop.Field` rendered offscreen at a device
/// scale. Shared by `launch-screen-renderer` (which writes it into the asset
/// catalog) and `LaunchScreenTests` (which checks the committed file is
/// still this), so neither can drift from the view.
@MainActor public enum LaunchImage {
    public static func render(scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: MenuBackdrop.Field())
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }
}
