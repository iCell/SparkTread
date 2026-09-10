import Foundation
import GameCore
#if canImport(GameController)
import GameController
#endif

/// Identifies who is holding an input: one physical key, one CONTROL of one
/// controller, the touch overlay. Aliases (W and UpArrow) and the buttons of
/// one gamepad are distinct sources, so releasing one never cancels another;
/// a device disconnect releases every source with that device's prefix.
public struct InputSource: Hashable, Sendable {
    public let id: String
    public init(_ id: String) { self.id = id }
    public static let `default` = InputSource("default")
    public static let touch = InputSource("touch")
    public static func key(_ name: String) -> InputSource { InputSource("keyboard:\(name)") }
    /// One control of one controller; `device` is stable for the life of
    /// the connection (object identity), never an enumeration index.
    public static func controller(_ device: String, control: String) -> InputSource {
        InputSource("\(controllerPrefix(device))\(control)")
    }
    public static func controllerPrefix(_ device: String) -> String { "controller:\(device):" }
    public static let keyboardPrefix = "keyboard:"
}

/// Resolves concurrent physical inputs into at most one held direction plus
/// the two fire buttons per tick (ADR-0002): the most recently pressed
/// direction wins; releasing it falls back to the next most recent
/// still-held press. Never inspects collision state — buffering and
/// assistance live in GameCore.
///
/// Fire semantics (adapter-side only): the normal cannon is EDGE-TRIGGERED
/// — one pulse per new press per source, no autofire on hold, no extra
/// edges from key repeat — while the special channel is hold-based.
@MainActor
public final class HeldDirectionStore {
    /// Press order, oldest first; the held direction is the last element.
    private var pressed: [(source: InputSource, direction: Direction)] = []
    private var normalHolders = Set<InputSource>()
    private var specialHolders = Set<InputSource>()
    /// Unconsumed normal-fire edges, per source, so a device that vanishes
    /// takes its own pending pulse with it.
    private var pendingNormalPulses = Set<InputSource>()

    /// Application-activity gate (§17.5): while inactive, presses are
    /// ignored rather than merely cleared once.
    public var isAcceptingInput = true

    /// Uptime of the last `releaseAll`; callbacks queued before it are stale.
    public private(set) var lastResetUptime: TimeInterval = 0
    /// An unconsumed pause/back press (§6.3 "pause/back"). NOT behind the
    /// activity gate: the same press resumes a paused game, when the gate
    /// is closed. Consumed by the view's flow timer, not the tick.
    private var pendingPause = false

    public init() {}

    public var held: Direction? { pressed.last?.direction }

    /// A press that is already held by this source is key repeat, not a new
    /// most-recent press: it keeps its priority slot.
    public func press(_ direction: Direction, from source: InputSource = .default) {
        guard isAcceptingInput else { return }
        guard !pressed.contains(where: { $0.source == source && $0.direction == direction }) else { return }
        pressed.append((source, direction))
    }

    public func release(_ direction: Direction, from source: InputSource = .default) {
        pressed.removeAll { $0.source == source && $0.direction == direction }
    }

    /// Releases every direction of one source (the stick lifted).
    public func release(from source: InputSource) {
        pressed.removeAll { $0.source == source }
    }

    /// Releases everything (restart, suspension); queued callbacks that
    /// observed an earlier uptime must not re-press afterwards.
    public func releaseAll() {
        pressed.removeAll()
        normalHolders.removeAll()
        specialHolders.removeAll()
        pendingNormalPulses.removeAll()
        lastResetUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Releases every input — held and pending — of the sources matching
    /// `predicate` (one device disconnecting). Other devices are untouched.
    public func releaseAll(where predicate: (InputSource) -> Bool) {
        pressed.removeAll { predicate($0.source) }
        normalHolders = normalHolders.filter { !predicate($0) }
        specialHolders = specialHolders.filter { !predicate($0) }
        pendingNormalPulses = pendingNormalPulses.filter { !predicate($0) }
    }

    /// Analog vector quantized to four directions with hysteresis (§6.3):
    /// the source's current direction is kept until another axis clearly
    /// dominates. Replaces only this source's contribution; an unchanged
    /// direction keeps its priority slot.
    public func updateFromAnalog(dx: Double, dy: Double, deadZone: Double,
                                 from source: InputSource = .default) {
        let current = pressed.last { $0.source == source }?.direction
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude >= deadZone else {
            pressed.removeAll { $0.source == source }
            return
        }
        guard isAcceptingInput else { return }
        let dominanceRatio = 1.15
        let candidate: Direction
        if abs(dx) > abs(dy) * dominanceRatio {
            candidate = dx > 0 ? .right : .left
        } else if abs(dy) > abs(dx) * dominanceRatio {
            candidate = dy > 0 ? .down : .up
        } else if let current {
            candidate = current // inside the hysteresis band: keep direction
        } else {
            candidate = abs(dx) >= abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
        }
        if current != candidate {
            pressed.removeAll { $0.source == source }
            pressed.append((source, candidate))
        }
    }

    // MARK: - Fire buttons

    /// A new holder produces one pulse; a source already holding (key
    /// repeat, duplicate events) produces none.
    public func pressNormalFire(from source: InputSource = .default) {
        guard isAcceptingInput else { return }
        if normalHolders.insert(source).inserted { pendingNormalPulses.insert(source) }
    }

    public func releaseNormalFire(from source: InputSource = .default) {
        normalHolders.remove(source)
    }

    /// Consumes every pending normal-fire pulse (once per tick): one shot
    /// however many sources pressed since the last tick.
    public func consumeNormalFirePulse() -> Bool {
        defer { pendingNormalPulses.removeAll() }
        return !pendingNormalPulses.isEmpty
    }

    /// A pause/back press edge (keyboard Escape/P, gamepad menu, the HUD
    /// button): one toggle per consume however many sources pressed.
    public func requestPause() { pendingPause = true }

    public func consumePauseRequest() -> Bool {
        defer { pendingPause = false }
        return pendingPause
    }

    public func pressSpecialFire(from source: InputSource = .default) {
        guard isAcceptingInput else { return }
        specialHolders.insert(source)
    }

    public func releaseSpecialFire(from source: InputSource = .default) {
        specialHolders.remove(source)
    }

    public var specialFireHeld: Bool { !specialHolders.isEmpty }
}

/// Per-device connection generations, readable from any thread: a
/// physical callback captures its device's generation when the event is
/// observed; delivery on the main actor drops it if the device has since
/// disconnected (generation bumped). Independent of the store's global
/// reset watermark used for restart/suspension.
public final class DeviceGenerations: @unchecked Sendable {
    private let lock = NSLock()
    private var generations: [String: Int] = [:]

    public init() {}

    public func current(_ device: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return generations[device, default: 0]
    }

    @discardableResult
    public func invalidate(_ device: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        generations[device, default: 0] += 1
        return generations[device]!
    }
}

/// The pure part of physical bindings, testable without GameController:
/// what a key or a gamepad control means, and how a physical event becomes
/// a main-actor store mutation that stale invalidation can drop.
public enum PhysicalBindings {
    public enum Action: Equatable, Sendable {
        case move(Direction)
        case normalFire
        case specialFire
        /// Pause/back (§6.3): an edge that toggles the pause overlay.
        case pause
    }

    /// Keyboard: arrows/WASD move, J/U normal fire, K/I special fire (the
    /// reference defaults, provisional), Escape/P pause. Keys are their
    /// own sources.
    public static let keyboard: [String: Action] = [
        "Up": .move(.up), "Right": .move(.right), "Down": .move(.down), "Left": .move(.left),
        "W": .move(.up), "D": .move(.right), "S": .move(.down), "A": .move(.left),
        "J": .normalFire, "U": .normalFire,
        "K": .specialFire, "I": .specialFire,
        "Escape": .pause, "P": .pause,
    ]

    /// Gamepad: A normal fire, B and X special fire, Menu pause — each its
    /// own control.
    public static let controllerButtons: [String: Action] = [
        "buttonA": .normalFire, "buttonB": .specialFire, "buttonX": .specialFire,
        "buttonMenu": .pause,
    ]

    /// Applies a digital action to the store for one source.
    @MainActor
    public static func apply(_ action: Action, pressed: Bool, from source: InputSource,
                             to store: HeldDirectionStore) {
        switch action {
        case .move(let direction):
            pressed ? store.press(direction, from: source) : store.release(direction, from: source)
        case .normalFire:
            pressed ? store.pressNormalFire(from: source) : store.releaseNormalFire(from: source)
        case .specialFire:
            pressed ? store.pressSpecialFire(from: source) : store.releaseSpecialFire(from: source)
        case .pause:
            if pressed { store.requestPause() }
        }
    }

    /// Delivers a physical event to the store on the main actor unless the
    /// device was invalidated (disconnected) after the event was observed,
    /// or a global `releaseAll` (restart/suspension) happened after it.
    public static func deliver(
        to store: HeldDirectionStore, device: String, generations: DeviceGenerations,
        _ body: @escaping @MainActor (HeldDirectionStore) -> Void
    ) {
        let observedAt = ProcessInfo.processInfo.systemUptime
        let observedGeneration = generations.current(device)
        Task { @MainActor in
            guard observedGeneration == generations.current(device),
                  observedAt >= store.lastResetUptime else { return }
            body(store)
        }
    }
}

#if canImport(GameController)
/// Hardware keyboard and game controllers → the held store, through
/// GameController so the same path serves keyboards and gamepads on iPhone,
/// iPad, and macOS. Each controller is identified by its object identity
/// for the life of its connection; each control is its own input source.
@MainActor
public final class PhysicalInputAdapter {
    private let store: HeldDirectionStore
    private let generations = DeviceGenerations()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init(store: HeldDirectionStore) {
        self.store = store
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCControllerDidConnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rewire() }
            })
        }
        // A device that goes away releases everything it was holding and
        // invalidates the callbacks it queued — only that device.
        observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.generations.invalidate("keyboard")
            Task { @MainActor in self.store.releaseAll { $0.id.hasPrefix(InputSource.keyboardPrefix) } }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            let device = Self.deviceID(controller)
            self.generations.invalidate(device)
            let prefix = InputSource.controllerPrefix(device)
            Task { @MainActor in self.store.releaseAll { $0.id.hasPrefix(prefix) } }
        })
        rewire()
    }

    nonisolated static func deviceID(_ controller: GCController) -> String {
        String(UInt(bitPattern: ObjectIdentifier(controller).hashValue), radix: 36)
    }

    /// (Re)wires every currently connected keyboard and controller. Input
    /// hot-plug stays outside authoritative simulation state (§17.4).
    private func rewire() {
        if let keyboard = GCKeyboard.coalesced { wire(keyboard: keyboard) }
        for controller in GCController.controllers() { wire(controller: controller) }
    }

    private func wire(keyboard: GCKeyboard) {
        let codes: [GCKeyCode: String] = [
            .upArrow: "Up", .rightArrow: "Right", .downArrow: "Down", .leftArrow: "Left",
            .keyW: "W", .keyD: "D", .keyS: "S", .keyA: "A",
            .keyJ: "J", .keyU: "U", .keyK: "K", .keyI: "I",
            .escape: "Escape", .keyP: "P",
        ]
        let store = self.store, generations = self.generations
        keyboard.keyboardInput?.keyChangedHandler = { _, _, keyCode, pressed in
            guard let name = codes[keyCode], let action = PhysicalBindings.keyboard[name] else { return }
            PhysicalBindings.deliver(to: store, device: "keyboard", generations: generations) {
                PhysicalBindings.apply(action, pressed: pressed, from: .key(name), to: $0)
            }
        }
    }

    private func wire(controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let store = self.store, generations = self.generations
        let device = Self.deviceID(controller)
        pad.dpad.valueChangedHandler = { _, x, y in
            // D-pad y is up-positive; world is Y-down.
            PhysicalBindings.deliver(to: store, device: device, generations: generations) {
                $0.updateFromAnalog(dx: Double(x), dy: Double(-y), deadZone: 0.5,
                                    from: .controller(device, control: "dpad"))
            }
        }
        let buttons: [(String, GCControllerButtonInput)] = [
            ("buttonA", pad.buttonA), ("buttonB", pad.buttonB), ("buttonX", pad.buttonX),
            ("buttonMenu", pad.buttonMenu),
        ]
        for (control, button) in buttons {
            guard let action = PhysicalBindings.controllerButtons[control] else { continue }
            button.pressedChangedHandler = { _, _, pressed in
                PhysicalBindings.deliver(to: store, device: device, generations: generations) {
                    PhysicalBindings.apply(action, pressed: pressed,
                                           from: .controller(device, control: control), to: $0)
                }
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
#endif
