import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppleAdapters

/// The launch image IS the title's backdrop (owner 2026-10-06): the page
/// iOS shows before the app runs must be a render of `MenuBackdrop.Field`,
/// or the hand-off into the launch sequence jumps. A changed backdrop has
/// to be re-baked with `swift run launch-screen-renderer`.
@Suite struct LaunchScreenTests {
    @Test @MainActor func theCommittedLaunchImageIsTheBackdrop() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/GoldenEagleApp/Assets.xcassets/LaunchBackdrop.imageset/launch_backdrop@3x.png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "launch image missing — run launch-screen-renderer")
        let committed = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let fresh = try #require(LaunchImage.render(scale: 3))
        #expect(committed.width == fresh.width && committed.height == fresh.height,
                "\(committed.width)×\(committed.height) vs \(fresh.width)×\(fresh.height)")
        #expect(fresh.width == Int(MenuBackdrop.fieldSize.width) * 3)
        // Same picture, allowing for PNG round-trip and renderer rounding;
        // a moved tile or a changed gradient is tens of levels off.
        let a = pixels(committed), b = pixels(fresh)
        var worst = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            for c in 0..<3 { worst = max(worst, abs(Int(a[i + c]) - Int(b[i + c]))) }
        }
        #expect(worst <= 3, "launch image differs from the backdrop by \(worst) levels — re-run launch-screen-renderer")
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
