import Testing
@testable import GameCore

@Suite("ArenaGeometry")
struct ArenaGeometryTests {
    @Test("arena constants are pinned")
    func constantsArePinned() {
        // 48x27 is fixed by ADR-0003; changing it requires a new ADR, not a test edit.
        #expect(ArenaGeometry.columns == 48)
        #expect(ArenaGeometry.rows == 27)
        #expect(ArenaGeometry.subunitsPerCell == 1024)
        #expect(ArenaGeometry.tankFootprintCells == 2)
    }

    @Test("arena extents derive from the cell counts")
    func extentsDerive() {
        #expect(ArenaGeometry.arenaWidthSubunits == 48 * 1024)
        #expect(ArenaGeometry.arenaHeightSubunits == 27 * 1024)
    }

    @Test("tick rate is 60 Hz")
    func tickRateIsPinned() {
        #expect(TickConstants.ticksPerSecond == 60)
    }

    @Test("a point inside a cell maps to that cell")
    func pointMapsToCell() {
        let point = SubunitPoint(x: 3 * 1024 + 500, y: 5 * 1024 + 1)
        #expect(point.cell == (3, 5))
    }

    @Test("a boundary point belongs to the cell it starts")
    func boundaryBelongsToStartingCell() {
        #expect(SubunitPoint(x: 0, y: 0).cell == (0, 0))
        #expect(SubunitPoint(x: 1023, y: 1023).cell == (0, 0))
        #expect(SubunitPoint(x: 1024, y: 1024).cell == (1, 1))
        #expect(SubunitPoint(x: 2047, y: 2047).cell == (1, 1))
    }

    @Test("the far corner is the last in-arena cell")
    func farCornerIsLastCell() {
        let lastInside = SubunitPoint(
            x: ArenaGeometry.arenaWidthSubunits - 1,
            y: ArenaGeometry.arenaHeightSubunits - 1
        )
        #expect(lastInside.cell == (47, 26))
    }

    @Test("cell initializer lands on the cell origin")
    func cellInitializerRoundTrips() {
        let point = SubunitPoint(column: 12, row: 9)
        #expect(point.x == 12 * 1024)
        #expect(point.y == 9 * 1024)
        #expect(point.cell == (12, 9))
    }

    @Test("negative coordinates floor rather than truncate toward zero")
    func negativeCoordinatesFloor() {
        // -1 subunit is outside the arena to the left, i.e. column -1, not column 0.
        #expect(SubunitPoint(x: -1, y: -1).cell == (-1, -1))
        #expect(SubunitPoint(x: -1024, y: -1024).cell == (-1, -1))
        #expect(SubunitPoint(x: -1025, y: -1025).cell == (-2, -2))
    }
}
