import CoreGraphics
import Testing
import GameCore
@testable import AppleAdapters

/// Device-aspect fixtures (§18.1 scene integration): the entire arena must
/// remain inside the gameplay viewport for every supported surface, with
/// uniform scale (no stretching) and edge-to-edge fit on at least one axis.
@Suite struct ArenaLayoutTests {
    /// Landscape point sizes: iPhone floor class through iPad.
    private static let surfaces: [(String, CGSize)] = [
        ("iPhone 12/13/14 class (floor)", CGSize(width: 844, height: 390)),
        ("iPhone 14/15/16/17 Pro class", CGSize(width: 852, height: 393)),
        ("iPhone 17", CGSize(width: 874, height: 402)),
        ("iPhone Pro Max class", CGSize(width: 932, height: 430)),
        ("iPad 11-inch", CGSize(width: 1194, height: 834)),
        ("iPad 13-inch", CGSize(width: 1376, height: 1032)),
    ]

    @Test func wholeArenaVisibleOnEverySupportedSurface() {
        for (name, surface) in Self.surfaces {
            let layout = ArenaLayout(surface: surface, arena: .universal)
            let rect = layout.arenaRect
            #expect(rect.minX >= -0.001 && rect.minY >= -0.001
                    && rect.maxX <= surface.width + 0.001
                    && rect.maxY <= surface.height + 0.001,
                    "arena leaves the viewport on \(name)")
            // Edge-to-edge on the constraining axis.
            let fillsWidth = abs(rect.width - surface.width) < 0.5
            let fillsHeight = abs(rect.height - surface.height) < 0.5
            #expect(fillsWidth || fillsHeight, "arena underfills both axes on \(name)")
        }
    }

    @Test func tankStaysInsideViewportAtEveryLegalPosition() {
        let arena = ArenaSpecification.universal
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for (name, surface) in Self.surfaces {
            let layout = ArenaLayout(surface: surface, arena: arena)
            // Extreme legal positions: the four corners of the movable range.
            for x in [0, arena.widthSubunits - footprint] {
                for y in [0, arena.heightSubunits - footprint] {
                    let rect = layout.sceneRect(topLeft: Vec2i(x: x, y: y),
                                                widthSubunits: footprint, heightSubunits: footprint)
                    #expect(layout.arenaRect.insetBy(dx: -0.001, dy: -0.001).contains(rect),
                            "tank at (\(x),\(y)) leaves the arena viewport on \(name)")
                }
            }
        }
    }

    @Test func conversionRoundTripsAndFlipsY() {
        let layout = ArenaLayout(surface: CGSize(width: 874, height: 402), arena: .universal)
        let topLeft = layout.scenePoint(Vec2i(x: 0, y: 0))
        let bottomRight = layout.scenePoint(Vec2i(
            x: ArenaSpecification.universal.widthSubunits,
            y: ArenaSpecification.universal.heightSubunits))
        #expect(topLeft.y > bottomRight.y) // Y-down world → Y-up scene
        #expect(bottomRight.x > topLeft.x)
        #expect(abs(topLeft.y - layout.arenaRect.maxY) < 0.001)
        #expect(abs(bottomRight.y - layout.arenaRect.minY) < 0.001)
    }

    /// Floor-device legibility record (ADR-0006): visible tank width on the
    /// pinned floor surface must clear the 18-point hard floor. The pixel
    /// art's visible bounding box is ~82% of the 2-cell footprint.
    @Test func tankMeetsLegibilityFloorOnFloorDevice() {
        let layout = ArenaLayout(surface: CGSize(width: 844, height: 390), arena: .universal)
        let footprintPoints = layout.cellPoints * 2
        let visibleWidth = footprintPoints * 0.82
        #expect(visibleWidth >= 18, "visible tank width \(visibleWidth) below ADR-0006 floor")
    }
}
