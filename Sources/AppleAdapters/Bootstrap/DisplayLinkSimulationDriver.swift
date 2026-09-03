#if canImport(UIKit)
import GameCore
import UIKit

/// The simulation clock authority (ADR-0007): a display-link-driven
/// fixed-timestep accumulator owned by the application adapter layer.
/// SpriteKit never advances, pauses, or gates the simulation.
@MainActor
public final class DisplayLinkSimulationDriver {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    /// Accumulated time in units of ticks (60ths of a second).
    private var accumulatedTicks: Double = 0
    private let stepTick: () -> Void

    /// Longer gaps route through explicit pause/resume, never a tick burst.
    private static let maxTicksPerCallback = 6

    public init(stepTick: @escaping () -> Void) {
        self.stepTick = stepTick
    }

    public func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    public func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        accumulatedTicks = 0
    }

    @objc private func fire(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        accumulatedTicks += (link.timestamp - last) * Double(MovementRuleset.ticksPerSecond)
        var whole = Int(accumulatedTicks)
        if whole > Self.maxTicksPerCallback {
            // Gap clamp: drop the excess instead of bursting (ADR-0007 §3).
            whole = Self.maxTicksPerCallback
            accumulatedTicks = Double(whole)
        }
        accumulatedTicks -= Double(whole)
        for _ in 0..<whole { stepTick() }
    }
}
#endif
