#if canImport(UIKit)
import GameCore
import UIKit

/// The simulation clock authority (ADR-0007): a display-link-driven
/// fixed-timestep accumulator owned by the application adapter layer.
/// SpriteKit never advances, pauses, or gates the simulation. The tick
/// arithmetic and stall policy live in `TickAccumulator`.
@MainActor
public final class DisplayLinkSimulationDriver {
    private var link: CADisplayLink?
    private var accumulator = TickAccumulator()
    private let stepTick: () -> Void
    /// Called when a frame gap exceeded the stall threshold (GAME_RULES
    /// §15.3): the game pauses instead of silently losing time.
    private let onStall: () -> Void

    public init(stepTick: @escaping () -> Void, onStall: @escaping () -> Void = {}) {
        self.stepTick = stepTick
        self.onStall = onStall
    }

    public var isRunning: Bool { link != nil }

    public func start() {
        guard link == nil else { return }
        accumulator.reset() // a fresh timestamp: no catch-up after a pause
        let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        // Preferred CALLBACK rate for the simulation driver = the tick rate
        // (a preference the system may not honour; SpriteKit renders on its
        // own schedule, so this does not guarantee one tick before every
        // rendered frame). Hypothesis: on a 120 Hz display the 60 Hz fixed
        // step otherwise lands on alternate callbacks (0,1,0,1 ticks) and a
        // long callback turns that into 0,1,1 — a plausible source of the
        // judder the owner saw under rapid fire, not a profiled cause. The
        // accumulator and its stall policy still decide how many ticks each
        // callback steps.
        let rate = Float(MovementRuleset.ticksPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    public func stop() {
        link?.invalidate()
        link = nil
        accumulator.reset()
    }

    @objc private func fire(_ link: CADisplayLink) {
        let stalls = accumulator.droppedStalls
        let whole = accumulator.advance(to: link.timestamp)
        if accumulator.droppedStalls != stalls {
            onStall()
            return
        }
        for _ in 0..<whole { stepTick() }
    }
}
#endif
