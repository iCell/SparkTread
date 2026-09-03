import GameApplication
import GameCore
import SpriteKit
import SwiftUI

/// Owns the Movement Lab wiring: session, input store, physical-input
/// adapter, and the display-link clock driver (composition per §14.2).
@MainActor
public final class MovementLabController {
    public private(set) var session: MovementLabSession
    public let input = HeldDirectionStore()
    #if canImport(GameController)
    private var physicalInput: PhysicalInputAdapter?
    #endif
    #if canImport(UIKit)
    private var driver: DisplayLinkSimulationDriver?
    #endif

    public init() {
        session = MovementLabSession()
        #if canImport(GameController)
        physicalInput = PhysicalInputAdapter(store: input)
        #endif
    }

    /// Launch-env autopilot for automated capture and demos; player input
    /// (touch/keyboard/controller) always overrides it when present.
    private let autodrive = ProcessInfo.processInfo.environment["MOVEMENT_LAB_AUTODRIVE"] != nil

    private func autodriveDirection(forTick tick: Int) -> Direction? {
        switch (tick % 1080) {
        case 0..<300: .down
        case 300..<540: .right
        case 540..<600: .up
        case 600..<840: .right
        case 840..<900: nil
        default: .up
        }
    }

    public func start() {
        #if canImport(UIKit)
        guard driver == nil else { return }
        let driver = DisplayLinkSimulationDriver { [weak self] in
            guard let self else { return }
            let scripted = self.autodrive ? self.autodriveDirection(forTick: self.session.world.tick) : nil
            self.session.advance(holding: self.input.held ?? scripted)
        }
        driver.start()
        self.driver = driver
        #endif
    }

    public func stop() {
        #if canImport(UIKit)
        driver?.stop()
        driver = nil
        #endif
    }
}

/// M1 Movement Lab: SpriteKit full-map presentation, touch joystick in the
/// left gutter, hardware keyboard (arrows/WASD) and controller D-pad.
public struct MovementLabView: View {
    @State private var controller = MovementLabController()
    @State private var scene: MovementLabScene?
    @State private var stickOrigin: CGPoint?
    @State private var stickOffset: CGSize = .zero

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: liveScene(for: geometry.size))
                    .ignoresSafeArea()
                joystickOverlay
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func liveScene(for size: CGSize) -> MovementLabScene {
        if let scene { return scene }
        // Scene matches the real device surface so the uniform fit is
        // computed against the true edge-to-edge bounds (ADR-0004).
        let created = MovementLabScene(
            size: size == .zero ? CGSize(width: 844, height: 390) : size,
            controller: controller)
        DispatchQueue.main.async { scene = created }
        return created
    }

    /// Floating virtual stick: appears where the finger lands, quantizes the
    /// drag vector to four directions with hysteresis (adapter-side only).
    private var joystickOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                if let origin = stickOrigin {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 96, height: 96)
                        .position(origin)
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .position(x: origin.x + stickOffset.width.clamped(to: -34...34),
                                  y: origin.y + stickOffset.height.clamped(to: -34...34))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if stickOrigin == nil { stickOrigin = value.startLocation }
                        stickOffset = value.translation
                        controller.input.updateFromAnalog(
                            dx: value.translation.width,
                            dy: value.translation.height,
                            deadZone: 12)
                    }
                    .onEnded { _ in
                        stickOrigin = nil
                        stickOffset = .zero
                        controller.input.releaseAll()
                    }
            )
        }
        .ignoresSafeArea()
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
