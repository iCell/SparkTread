// Bakes `MenuBackdrop.Field` — the title screen's backdrop — into the app's
// launch image (owner 2026-10-06: the page iOS shows before the app runs
// should flow into the launch sequence rather than be a black card).
//
// A launch screen runs no code and shows ONE image centred at its intrinsic
// size over a colour (Info.plist UILaunchScreen), so the live backdrop is
// composed on the same fixed field, centred, and this renders that field at
// 2× and 3× into the asset catalog. `LaunchScreenTests` fails when the
// committed image no longer matches a fresh render, so a change to the
// backdrop cannot ship without re-running:   swift run launch-screen-renderer
import AppleAdapters
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let imageSet = root.appendingPathComponent("Sources/GoldenEagleApp/Assets.xcassets/LaunchBackdrop.imageset")

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
    for scale in [2, 3] {
        guard let image = LaunchImage.render(scale: CGFloat(scale)) else { fatalError("render failed") }
        let url = imageSet.appendingPathComponent("launch_backdrop@\(scale)x.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("cannot create \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
        print("\(url.lastPathComponent)  \(image.width)×\(image.height)")
    }
    let contents = """
    {
      "images" : [
        { "filename" : "launch_backdrop@2x.png", "idiom" : "universal", "scale" : "2x" },
        { "filename" : "launch_backdrop@3x.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try! contents.write(to: imageSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
