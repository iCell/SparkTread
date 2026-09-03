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
    /// Fire button states, held by the UI overlay (adapter-side only).
    public var normalFireHeld = false
    public var specialFireHeld = false
    /// Events since the scene last drained them (presentation feed).
    private var pendingEvents: [DomainEvent] = []
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
            let tick = self.session.world.tick
            let scripted = self.autodrive ? self.autodriveDirection(forTick: tick) : nil
            let scriptedNormal = self.autodrive && tick % 45 < 2
            let scriptedSpecial = self.autodrive && tick % 130 < 2
            self.session.debugRespawnPlayerIfNeeded()
            self.pendingEvents += self.session.advance(
                holding: self.input.held ?? scripted,
                normalFire: self.normalFireHeld || scriptedNormal,
                specialFire: self.specialFireHeld || scriptedSpecial)
        }
        driver.start()
        self.driver = driver
        #endif
    }

    public func drainEvents() -> [DomainEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    // MARK: - Weapon debug panel

    public let specialWeaponIDs = ["rapid", "fire", "ap", "explosion", "mine"]

    public func selectWeapon(_ id: String) { session.debugSelectSpecialWeapon(id) }
    public func setPower(_ level: Int) { session.debugSetPowerLevel(level) }

    public var playerTank: TankState? {
        session.world.player(.one)?.tankEntityID.flatMap { session.world.tank(entityID: $0) }
    }

    public var currentAmmo: Int {
        guard let tank = playerTank else { return 0 }
        return session.world.player(.one)?.specialAmmoByWeapon[tank.specialWeaponID] ?? 0
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

    @State private var selectedWeapon = "rapid"
    @State private var powerLevel = 0
    @State private var showWeaponPanel = false

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: liveScene(for: geometry.size))
                    .ignoresSafeArea()
                joystickOverlay
                fireButtons
                weaponDebugPanel
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    /// Normal + special fire, right thumb zone. Hold-to-fire semantics.
    private var fireButtons: some View {
        VStack(spacing: 14) {
            fireButton(label: "特", color: .orange, held: { controller.specialFireHeld = $0 })
            fireButton(label: "普", color: .cyan, held: { controller.normalFireHeld = $0 })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 28)
        .padding(.bottom, 24)
    }

    private func fireButton(label: String, color: Color, held: @escaping (Bool) -> Void) -> some View {
        Text(label)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 62, height: 62)
            .background(Circle().fill(color.opacity(0.45)))
            .overlay(Circle().strokeBorder(color.opacity(0.9), lineWidth: 2))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in held(true) }
                .onEnded { _ in held(false) })
    }

    /// Weapon debug panel (M2 deliverable): special-weapon selector and
    /// power-level control, top-right, collapsible.
    private var weaponDebugPanel: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(showWeaponPanel ? "武器 ▲" : "武器 ▼") { showWeaponPanel.toggle() }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
            if showWeaponPanel {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(controller.specialWeaponIDs, id: \.self) { id in
                        Button(id) {
                            selectedWeapon = id
                            controller.selectWeapon(id)
                        }
                        .font(.system(size: 12, weight: selectedWeapon == id ? .bold : .regular))
                        .foregroundStyle(selectedWeapon == id ? .yellow : .white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { level in
                            Button("P\(level)") {
                                powerLevel = level
                                controller.setPower(level)
                            }
                            .font(.system(size: 11, weight: powerLevel == level ? .bold : .regular))
                            .foregroundStyle(powerLevel == level ? .yellow : .white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 16)
        .padding(.top, 8)
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
