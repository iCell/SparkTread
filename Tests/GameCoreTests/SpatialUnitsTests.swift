import Testing
@testable import GameCore

@Suite struct SpatialUnitsTests {
    @Test func cellQuadrantAndTankRelationsHold() {
        #expect(SpatialUnits.subunitsPerCell == 1024)
        #expect(SpatialUnits.subunitsPerQuadrant * 2 == SpatialUnits.subunitsPerCell)
        #expect(SpatialUnits.standardTankFootprintSubunits == 2 * SpatialUnits.subunitsPerCell)
    }

    /// ADR-0001: the documented reference conversion is itself covered by a
    /// unit test against known reference values.
    @Test func referencePixelConversionMatchesKnownValues() {
        #expect(SpatialUnits.subunitsPerReferencePixel == 64)
        // A 16-pixel reference cell converts to exactly one modern cell.
        #expect(16 * SpatialUnits.subunitsPerReferencePixel == SpatialUnits.subunitsPerCell)
        // An 8-pixel reference quadrant converts to exactly one destruction quadrant.
        #expect(8 * SpatialUnits.subunitsPerReferencePixel == SpatialUnits.subunitsPerQuadrant)
    }

    @Test func perTickDisplacementCapStaysBelowOneCell() {
        #expect(SpatialUnits.maxPerTickDisplacementSubunits < SpatialUnits.subunitsPerCell)
    }
}

@Suite struct ArenaSpecificationTests {
    @Test func universalArenaIs56By27() {
        // Pinned by ADR-0009 (the one-shot M1 dimension tuning).
        let arena = ArenaSpecification.universal
        #expect(arena.cellsWide == 56)
        #expect(arena.cellsHigh == 27)
        #expect(arena.widthSubunits == 56 * 1024)
        #expect(arena.heightSubunits == 27 * 1024)
    }
}
