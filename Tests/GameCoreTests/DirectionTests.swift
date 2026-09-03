import Testing
@testable import GameCore

@Suite("Direction")
struct DirectionTests {
    @Test("opposite is involutive for every case", arguments: Direction.allCases)
    func oppositeIsInvolutive(direction: Direction) {
        #expect(direction.opposite.opposite == direction)
        #expect(direction.opposite != direction)
    }

    @Test("vectors are unit sign vectors")
    func vectorsAreUnitSignVectors() {
        for direction in Direction.allCases {
            let (dx, dy) = direction.vector
            // Exactly one axis moves, by exactly one step.
            #expect(abs(dx) + abs(dy) == 1)
        }
    }

    @Test("y grows downward, so up is negative and mirrors down")
    func verticalAxisPointsDown() {
        #expect(Direction.up.vector == (0, -1))
        #expect(Direction.down.vector == (0, 1))
        #expect(Direction.left.vector == (-1, 0))
        #expect(Direction.right.vector == (1, 0))
    }

    @Test("opposite directions have negated vectors")
    func oppositeVectorsMirror() {
        for direction in Direction.allCases {
            let forward = direction.vector
            let backward = direction.opposite.vector
            #expect(forward.dx == -backward.dx)
            #expect(forward.dy == -backward.dy)
        }
    }

    @Test("raw values round-trip and stay pinned")
    func rawValueRoundTrip() {
        for direction in Direction.allCases {
            #expect(Direction(rawValue: direction.rawValue) == direction)
            #expect(Direction(index: direction.rawValue) == direction)
        }
        // Pinned because raw values are serialized into replays and content.
        #expect(Direction.up.rawValue == 0)
        #expect(Direction.right.rawValue == 1)
        #expect(Direction.down.rawValue == 2)
        #expect(Direction.left.rawValue == 3)
        #expect(Direction(index: 4) == nil)
        #expect(Direction(index: -1) == nil)
    }
}
