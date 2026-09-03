import Testing
@testable import GameCore

@Suite("DeterministicRNG")
struct DeterministicRNGTests {
    private func draw(seed: UInt64, count: Int) -> [UInt64] {
        var rng = DeterministicRNG(seed: seed)
        return (0..<count).map { _ in rng.nextUInt64() }
    }

    @Test("the same seed reproduces the same sequence")
    func sameSeedSameSequence() {
        #expect(draw(seed: 0xDEAD_BEEF, count: 100) == draw(seed: 0xDEAD_BEEF, count: 100))
    }

    @Test("different seeds diverge")
    func differentSeedsDiffer() {
        #expect(draw(seed: 1, count: 100) != draw(seed: 2, count: 100))
        // A zero seed must still produce a usable stream.
        #expect(draw(seed: 0, count: 100) != draw(seed: 1, count: 100))
    }

    @Test("named streams from one world seed are pairwise independent")
    func streamsArePairwiseDifferent() {
        var streams = RNGStreams(worldSeed: 0x5EED_5EED)
        let ai = (0..<100).map { _ in streams.ai.nextUInt64() }
        let spawn = (0..<100).map { _ in streams.spawn.nextUInt64() }
        let drop = (0..<100).map { _ in streams.drop.nextUInt64() }

        #expect(ai != spawn)
        #expect(ai != drop)
        #expect(spawn != drop)
    }

    @Test("streams are reproducible from the world seed")
    func streamsAreReproducible() {
        var first = RNGStreams(worldSeed: 42)
        var second = RNGStreams(worldSeed: 42)
        #expect(first.ai.nextUInt64() == second.ai.nextUInt64())
        #expect(first.spawn.nextUInt64() == second.spawn.nextUInt64())
        #expect(first.drop.nextUInt64() == second.drop.nextUInt64())
    }

    @Test("draining one stream does not perturb the others")
    func streamsDoNotInterfere() {
        var untouched = RNGStreams(worldSeed: 7)
        var drained = RNGStreams(worldSeed: 7)
        for _ in 0..<1_000 { _ = drained.ai.nextUInt64() }

        #expect(untouched.spawn.nextUInt64() == drained.spawn.nextUInt64())
        #expect(untouched.drop.nextUInt64() == drained.drop.nextUInt64())
    }

    @Test("next(upperBound:) stays in range", arguments: [1, 2, 3, 5, 7, 255, 1000] as [UInt32])
    func boundedDrawsStayInRange(upperBound: UInt32) {
        var rng = DeterministicRNG(seed: 0xC0FFEE)
        for _ in 0..<10_000 {
            #expect(rng.next(upperBound: upperBound) < upperBound)
        }
    }

    @Test("next(upperBound:) reaches every value of a small range")
    func boundedDrawsCoverRange() {
        var rng = DeterministicRNG(seed: 99)
        var seen = Set<UInt32>()
        for _ in 0..<10_000 { seen.insert(rng.next(upperBound: 4)) }
        #expect(seen == [0, 1, 2, 3])
    }
}
