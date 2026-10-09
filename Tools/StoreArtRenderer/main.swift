// Composes the App Store screenshots and the preview video's caption cards
// (owner 2026-10-09: not bare captures — edited, more attractive, in at least
// English, Simplified and Traditional Chinese and Japanese).
//
//   swift run store-art-renderer <frames.json>
//
// `Tools/StoreMedia/compose.py` writes the frame list: per frame an output
// path, a pixel size, a layout and its texts. Layouts:
//   side        landscape iPhone: caption column left, the capture right
//   top         iPad: caption above, the capture below
//   lowerThird  transparent caption plate for the preview (ffmpeg overlays it)
//   endCard     the preview's closing card: wordmark, tagline, facts
// Everything is drawn with the app's own pieces (`BrandArt`): the steel
// plate, the wordmark, its extruded fire-and-steel lettering.
import AppleAdapters
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct FrameSpec: Decodable {
    let out: String
    let width: Double
    let height: Double
    let layout: String
    let lang: String
    let shot: String?
    let headline: String
    let subline: String
    /// Tank sprites shown under the caption: archetype ids, or "player".
    let icons: [String]?
    /// A region of the capture (x, y, width, height in its pixels) shown
    /// magnified in a callout: the action is small on a 56-cell field.
    let zoom: [Double]?
    /// The first slot: the wordmark heads the caption column.
    let hero: Bool?
}

struct FrameList: Decodable { let frames: [FrameSpec] }

// MARK: - Materials

enum Palette {
    static let fireFace = LinearGradient(colors: [Color(red: 1.00, green: 0.88, blue: 0.30),
                                                  Color(red: 1.00, green: 0.62, blue: 0.08)],
                                         startPoint: .top, endPoint: .bottom)
    static let fireSide = Color(red: 0.46, green: 0.22, blue: 0.02)
    static let steelFace = LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 0.97),
                                                   Color(red: 0.62, green: 0.69, blue: 0.74)],
                                          startPoint: .top, endPoint: .bottom)
    static let steelEdge = LinearGradient(colors: [Color(red: 0.62, green: 0.70, blue: 0.76),
                                                   Color(red: 0.24, green: 0.30, blue: 0.35)],
                                          startPoint: .top, endPoint: .bottom)
    static let fire = Color(red: 1.00, green: 0.74, blue: 0.16)
}

/// The steel plate the menus stand on, lit from the top, warm where the
/// caption sits.
struct StoreBackdrop: View {
    var glow: UnitPoint = .leading
    var body: some View {
        ZStack {
            BrandArt.baseColor
            if let tile = BrandArt.plateTile(scale: 6) {
                Image(decorative: tile, scale: 1)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .opacity(0.24)
                    .blendMode(.plusLighter)
            }
            LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.fire.opacity(0.22), .clear], center: glow, startRadius: 0, endRadius: 1100)
            RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 500, endRadius: 1700)
        }
    }
}

/// Lettering in the wordmark's manner: a face, a hard black rim, a stepped
/// extrusion — no blur, so it keeps pixel art's edges.
struct Extruded: View {
    let text: String
    let size: CGFloat
    var face: LinearGradient = Palette.fireFace
    var side: Color = Palette.fireSide
    var alignment: TextAlignment = .leading

    var body: some View {
        let depth = max(2, Int(size / 13))
        let rim = max(1.5, size / 40)
        ZStack {
            ForEach(1...depth, id: \.self) { step in
                label.foregroundStyle(side).offset(x: CGFloat(step), y: CGFloat(step))
            }
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                label.foregroundStyle(Color.black).offset(x: rim * cos(angle), y: rim * sin(angle))
            }
            label.foregroundStyle(face)
        }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .multilineTextAlignment(alignment)
            .lineSpacing(size * 0.08)
            .handBroken(text)
    }
}

struct Subline: View {
    let text: String
    let size: CGFloat
    var alignment: TextAlignment = .leading
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.steelFace)
            .multilineTextAlignment(alignment)
            .lineSpacing(size * 0.25)
            .shadow(color: .black.opacity(0.8), radius: 0, x: 2, y: 2)
            .handBroken(text)
    }
}

extension View {
    /// A caption broken by hand keeps its breaks: the lines shrink to fit
    /// the column instead of wrapping again mid-word (CJK wraps anywhere).
    /// Unbroken text wraps freely.
    @ViewBuilder func handBroken(_ text: String) -> some View {
        if text.contains("\n") {
            self.lineLimit(text.components(separatedBy: "\n").count).minimumScaleFactor(0.5)
        } else {
            self.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A capture in a steel bezel with a hard shadow.
struct ShotCard: View {
    let image: CGImage
    let width: CGFloat
    var body: some View {
        let height = width * CGFloat(image.height) / CGFloat(image.width)
        let radius = width * 0.02
        let bezel = width * 0.007
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(bezel)
            .background(RoundedRectangle(cornerRadius: radius + bezel, style: .continuous).fill(Palette.steelEdge))
            .overlay(RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)
                .strokeBorder(Color.black, lineWidth: bezel * 0.35))
            .shadow(color: .black.opacity(0.7), radius: width * 0.018, x: 0, y: width * 0.01)
    }
}

/// The capture with an optional callout: the region outlined in fire
/// yellow on the frame, and magnified — nearest-neighbour, so the pixels
/// stay pixels — in an inset over the frame's lower-left corner.
struct ZoomedShot: View {
    let image: CGImage
    let width: CGFloat
    let zoom: [Double]?
    /// Corners the callout may take: never over the caption.
    var corners: [Alignment] = [.topTrailing, .bottomTrailing]
    /// How far the callout reaches past the card, as a share of its size.
    var outset: CGFloat = 0.1
    var body: some View {
        let scale = width / CGFloat(image.width)
        let height = CGFloat(image.height) * scale
        ShotCard(image: image, width: width)
            .overlay(alignment: .topLeading) {
                if let r = region {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.fire, lineWidth: max(4, width * 0.0025))
                        .frame(width: r.width * scale, height: r.height * scale)
                        .offset(x: width * 0.007 + r.minX * scale, y: width * 0.007 + r.minY * scale)
                }
            }
            .overlay(alignment: calloutCorner) {
                if let r = region, let crop = image.cropping(to: r) {
                    let insetWidth = width * 0.36
                    let insetHeight = insetWidth * r.height / r.width
                    Image(decorative: crop, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: insetWidth, height: insetHeight)
                        .clipShape(RoundedRectangle(cornerRadius: insetWidth * 0.03, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: insetWidth * 0.03, style: .continuous)
                            .strokeBorder(Palette.fire, lineWidth: insetWidth * 0.012))
                        .overlay(RoundedRectangle(cornerRadius: insetWidth * 0.03, style: .continuous)
                            .strokeBorder(Color.black, lineWidth: insetWidth * 0.004).padding(-insetWidth * 0.004))
                        .shadow(color: .black.opacity(0.75), radius: insetWidth * 0.03, x: 0, y: insetWidth * 0.015)
                        .offset(x: calloutCorner == .bottomLeading || calloutCorner == .topLeading ? -width * 0.035 : width * 0.03,
                                y: calloutCorner == .bottomLeading || calloutCorner == .bottomTrailing ? height * outset : -height * outset)
                }
            }
    }

    /// The callout sits over the corner farthest from what it magnifies.
    private var calloutCorner: Alignment {
        guard let r = region else { return corners[0] }
        func point(_ a: Alignment) -> CGPoint {
            CGPoint(x: a == .topLeading || a == .bottomLeading ? 0 : CGFloat(image.width),
                    y: a == .topLeading || a == .topTrailing ? 0 : CGFloat(image.height))
        }
        return corners.max { a, b in
            hypot(point(a).x - r.midX, point(a).y - r.midY) < hypot(point(b).x - r.midX, point(b).y - r.midY)
        } ?? corners[0]
    }

    private var region: CGRect? {
        guard let z = zoom, z.count == 4 else { return nil }
        return CGRect(x: z[0], y: z[1], width: z[2], height: z[3]).integral
    }
}

/// A row of the arena's own tank sprites, pixel-exact.
struct TankRow: View {
    let ids: [String]
    let height: CGFloat
    var body: some View {
        HStack(spacing: height * 0.35) {
            ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                if let image = id == "player" ? BrandArt.playerTank : BrandArt.tankIcon(archetypeID: id) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: height)
                        .shadow(color: .black.opacity(0.8), radius: 0, x: height * 0.06, y: height * 0.06)
                }
            }
        }
    }
}

/// The yellow bar the menus accent a selection with.
struct AccentBar: View {
    let length: CGFloat
    let thickness: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: thickness / 2).fill(Palette.fireFace).frame(width: length, height: thickness)
            .overlay(RoundedRectangle(cornerRadius: thickness / 2).strokeBorder(Color.black, lineWidth: 2))
    }
}

// MARK: - Layouts

@MainActor @ViewBuilder
func frameView(_ spec: FrameSpec) -> some View {
    let w = spec.width, h = spec.height
    let shot = spec.shot.flatMap(loadImage)
    switch spec.layout {
    case "side":
        let cardWidth = w * 0.655
        ZStack {
            StoreBackdrop(glow: UnitPoint(x: 0.1, y: 0.5))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: h * 0.045) {
                    if spec.hero == true {
                        BrandArt.wordmark.scaleEffect(h / 720, anchor: .leading)
                            .frame(width: w * 0.255, height: h * 0.2, alignment: .leading)
                    } else {
                        AccentBar(length: w * 0.05, thickness: h * 0.014)
                    }
                    Extruded(text: spec.headline, size: spec.hero == true ? h * 0.07 : h * 0.095)
                    Subline(text: spec.subline, size: h * 0.038)
                    if let icons = spec.icons { TankRow(ids: icons, height: h * 0.075).padding(.top, h * 0.02) }
                }
                .frame(width: w * 0.255, alignment: .leading)
                .padding(.leading, w * 0.034)
                Spacer(minLength: 0)
                if let shot { ZoomedShot(image: shot, width: cardWidth, zoom: spec.zoom) }
            }
            .padding(.trailing, w * 0.032)
        }
    case "top":
        ZStack {
            StoreBackdrop(glow: UnitPoint(x: 0.5, y: 0.05))
            VStack(spacing: h * 0.03) {
                Extruded(text: spec.headline, size: h * 0.06, alignment: .center)
                Subline(text: spec.subline, size: h * 0.026, alignment: .center)
                if let icons = spec.icons { TankRow(ids: icons, height: h * 0.045) }
                Spacer(minLength: h * 0.01)
                if let shot { ZoomedShot(image: shot, width: w * 0.66, zoom: spec.zoom,
                                         corners: [.bottomLeading, .bottomTrailing], outset: -0.03) }
            }
            .padding(.top, h * 0.06)
            .padding(.bottom, h * 0.055)
            .frame(width: w * 0.9)
        }
    case "lowerThird":
        ZStack(alignment: .bottomLeading) {
            Color.clear
            HStack(spacing: h * 0.03) {
                AccentBar(length: h * 0.016, thickness: h * 0.16).rotationEffect(.zero)
                    .frame(width: h * 0.016, height: h * 0.16)
                VStack(alignment: .leading, spacing: h * 0.012) {
                    Extruded(text: spec.headline, size: h * 0.075)
                    Subline(text: spec.subline, size: h * 0.034)
                }
            }
            .padding(.horizontal, h * 0.04)
            .padding(.vertical, h * 0.03)
            .background(RoundedRectangle(cornerRadius: h * 0.025, style: .continuous).fill(Color.black.opacity(0.62)))
            .overlay(RoundedRectangle(cornerRadius: h * 0.025, style: .continuous)
                .strokeBorder(Palette.steelEdge, lineWidth: 3))
            .padding(.leading, h * 0.06)
            .padding(.bottom, h * 0.07)
        }
    default: // endCard
        ZStack {
            StoreBackdrop(glow: UnitPoint(x: 0.5, y: 0.42))
            VStack(spacing: h * 0.05) {
                BrandArt.wordmark.scaleEffect(h / 300).frame(height: h * 0.34)
                Extruded(text: spec.headline, size: h * 0.07, face: Palette.steelFace,
                         side: Color(red: 0.09, green: 0.13, blue: 0.16), alignment: .center)
                Subline(text: spec.subline, size: h * 0.036, alignment: .center)
                if let icons = spec.icons { TankRow(ids: icons, height: h * 0.07) }
            }
        }
    }
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot create \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(path)") }
}

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
MainActor.assumeIsolated {
    BrandArt.useArt(root: repositoryRoot.appendingPathComponent("Vendor/SparkTreadPixel"))
    if BrandArt.plateTile(scale: 6) == nil { fatalError("the steel plate sprite did not load from Vendor/SparkTreadPixel") }
}
guard CommandLine.arguments.count == 2,
      let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let list = try? JSONDecoder().decode(FrameList.self, from: data)
else { fatalError("usage: store-art-renderer <frames.json>") }

MainActor.assumeIsolated {
    for spec in list.frames {
        let view = frameView(spec)
            .frame(width: spec.width, height: spec.height)
            .environment(\.locale, Locale(identifier: spec.lang))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = spec.layout != "lowerThird"
        guard let image = renderer.cgImage else { fatalError("render failed: \(spec.out)") }
        write(image, to: spec.out)
        print("\(spec.out)  \(image.width)×\(image.height)")
    }
}
