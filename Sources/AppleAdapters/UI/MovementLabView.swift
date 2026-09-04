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
    /// Fire input semantics (adapter-side only): the normal cannon is
    /// EDGE-TRIGGERED — one shell per press, no autofire on hold — while the
    /// special channel is hold-based (rapid's identity is sustained fire).
    public var specialFireHeld = false
    private var normalFirePulse = false
    public func pressNormalFire() { normalFirePulse = true }
    /// Events since the scene last drained them (presentation feed).
    private var pendingEvents: [DomainEvent] = []
    #if canImport(GameController)
    private var physicalInput: PhysicalInputAdapter?
    #endif
    #if canImport(UIKit)
    private var driver: DisplayLinkSimulationDriver?
    #endif

    public init() {
        // VS-01 is the app's playable stage; MOVEMENT_LAB=1 launches the
        // free-play movement/combat lab world instead.
        let useLab = ProcessInfo.processInfo.environment["MOVEMENT_LAB"] != nil
        session = useLab ? MovementLabSession() : MovementLabSession(world: VS01Stage.makeWorld())
        #if canImport(GameController)
        physicalInput = PhysicalInputAdapter(store: input)
        #endif
    }

    /// Bumped whenever the world is rebuilt so the scene knows to rebuild
    /// its static layers.
    public private(set) var worldGeneration = 0

    public func restart() {
        session.restartStage()
        worldGeneration += 1
    }

    public var stagePhase: StagePhase? { session.world.stage?.phase }
    public var hud: (lives: Int, score: Int, enemiesLeft: Int, baseHP: Int, shield: Bool) {
        let world = session.world
        let player = world.player(.one)
        let enemiesLeft = (world.stage?.spawnQueue.count ?? 0)
            + world.spawnTelegraphs.count
            + world.tanks.filter { $0.teamID != 1 }.count
        return (player?.lives ?? 0, player?.score ?? 0, enemiesLeft,
                world.base?.durability ?? 0, (world.base?.shieldRemainingTicks ?? 0) > 0)
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
            let normalPulse = self.normalFirePulse
            self.normalFirePulse = false
            self.pendingEvents += self.session.advance(
                holding: self.input.held ?? scripted,
                normalFire: normalPulse || scriptedNormal,
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

    public init() {}

    @State private var selectedWeapon = "rapid"
    @State private var powerLevel = 0
    @State private var showWeaponPanel = false
    @State private var hudTick = 0

    private let hudTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: liveScene(for: geometry.size))
                    .ignoresSafeArea()
                #if canImport(UIKit)
                TouchControlsView(controller: controller)
                    .ignoresSafeArea()
                #endif
                weaponDebugPanel
                stageHUD
                resultOverlay
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onReceive(hudTimer) { _ in hudTick &+= 1 }
    }

    /// Provisional stage HUD (§12.2 subset): lives, enemies remaining, base
    /// durability/shield, score. Safe-area-aware overlay on the arena.
    @ViewBuilder private var stageHUD: some View {
        if controller.stagePhase != nil {
            let hud = controller.hud
            HStack(spacing: 18) {
                Label("\(hud.lives)", systemImage: "heart.fill").foregroundStyle(.red)
                Label("\(hud.enemiesLeft)", systemImage: "shield.lefthalf.filled").foregroundStyle(.orange)
                Label("\(hud.baseHP)\(hud.shield ? "🛡" : "")", systemImage: "house.fill")
                    .foregroundStyle(hud.baseHP > 1 ? .green : .red)
                Text("\(hud.score)").foregroundStyle(.yellow)
            }
            .id(hudTick)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 6)
        }
    }

    /// Win/loss overlay with restart (stage flow, M3).
    @ViewBuilder private var resultOverlay: some View {
        if let phase = controller.stagePhase, phase != .playing {
            let won = phase == .won
            VStack(spacing: 16) {
                Text(won ? "任务完成" : "基地失守")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(won ? Color.yellow : Color.red)
                Text("得分 \(controller.hud.score)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Button {
                    controller.restart()
                } label: {
                    Text("重新开始")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 26).padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                }
            }
            .id(hudTick)
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.75)))
        }
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
}
