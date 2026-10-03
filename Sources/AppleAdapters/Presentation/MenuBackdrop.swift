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
