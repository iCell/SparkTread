import Foundation
import GameCore
#if os(iOS)
import UIKit
#endif

/// Haptic layer beside GameAudio: domain events → feedback cues, filtered
/// to moments the PLAYER feels (own shots, own damage, kills, base danger,
/// stage outcome) — enemy activity elsewhere never buzzes the hand.
@MainActor
public final class GameHaptics {
    public enum Cue: Equatable {
        /// The player's own shot: a light impact, throttled (see `admit`).
        case recoil
        case light(intensity: Double)
        case medium
        case heavy
        case success
        case warning
        case error
    }

    public var isEnabled = true
    /// Application-activity gate: no cues while inactive.
    public private(set) var isSuspended = false
    public func suspend() { isSuspended = true }
    public func resume() { isSuspended = false }

    #if os(iOS)
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notifyGenerator = UINotificationFeedbackGenerator()
    #endif

    /// Monotonic clock for the recoil throttle — never calendar time.
    private let clock: () -> TimeInterval

    public init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        #if os(iOS)
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        notifyGenerator.prepare()
        #endif
    }

    /// Own-recoil impacts are throttled: rapid fire reaches twelve shots a
    /// second, and a Taptic impact per shot both buzzes and costs main-thread
    /// time each frame. Other cues are never throttled.
    public nonisolated static let recoilMinimumInterval: TimeInterval = 0.12
    private var lastRecoilTime: TimeInterval?

    public func play(events: [DomainEvent]) {
        guard isEnabled, !isSuspended else { return }
        for cue in admit(Self.cues(for: events), now: clock()) {
            play(cue)
        }
    }

    /// The cues that pass the recoil throttle at `now`; commits the throttle.
    func admit(_ cues: [Cue], now: TimeInterval) -> [Cue] {
        cues.filter { cue in
            guard cue == .recoil else { return true }
            // Numerical-scale tolerance only (R18-02): 0.119 s is rejected,
            // 0.12 s admitted, at any realistic clock origin.
            if let last = lastRecoilTime, now - last < Self.recoilMinimumInterval - 1e-9 { return false }
            lastRecoilTime = now
            return true
        }
    }

    private func play(_ cue: Cue) {
        #if os(iOS)
        switch cue {
        case .recoil: lightGenerator.impactOccurred(intensity: 0.5)
        case .light(let intensity): lightGenerator.impactOccurred(intensity: intensity)
        case .medium: mediumGenerator.impactOccurred()
        case .heavy: heavyGenerator.impactOccurred()
        case .success: notifyGenerator.notificationOccurred(.success)
        case .warning: notifyGenerator.notificationOccurred(.warning)
        case .error: notifyGenerator.notificationOccurred(.error)
        }
        #endif
    }

    /// Pure event→cue resolution (deduplicated), separated for tests.
    public nonisolated static func cues(for events: [DomainEvent]) -> [Cue] {
        var cues: [Cue] = []
        func add(_ cue: Cue) {
            if !cues.contains(cue) { cues.append(cue) }
        }
        let stageDecided = events.contains {
            if case .stageWon = $0 { return true }
            if case .stageLost = $0 { return true }
            return false
        }
        for event in events {
            switch event {
            case .weaponFired(_, let owner, _, _, _, _) where owner != nil:
                add(.recoil) // own recoil only
            case .tankDamaged(_, let owner, _, _, _):
                add(owner != nil ? .medium : .light(intensity: 0.8)) // hurt vs hit-confirm
            case .tankShieldHit(_, let owner, _, _) where owner != nil:
                add(.light(intensity: 0.7))
            case .tankDestroyed(_, let owner, _):
                add(owner != nil ? .heavy : .medium)
            case .baseDamaged(_, _, let allied):
                // ADR-0005: own fire feels like a mistake (error), an enemy
                // breakthrough like an alarm (warning + heavy).
                if allied {
                    add(.error)
                } else {
                    if !stageDecided { add(.warning) }
                    add(.heavy)
                }
            case .pickupCollected:
                add(.success)
            case .stageWon:
                add(.success)
            case .stageLost:
                add(.error)
            default:
                break
            }
        }
        return cues
    }
}
