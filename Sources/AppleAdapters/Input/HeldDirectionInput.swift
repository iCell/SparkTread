import GameCore
#if canImport(GameController)
import GameController
#endif

/// Resolves concurrent physical inputs into at most one held direction per
/// tick (ADR-0002): the most recently pressed direction wins; releasing it
/// falls back to the next most recent still-held press. Never inspects
/// collision state — buffering and assistance live in GameCore.
@MainActor
public final class HeldDirectionStore {
    /// Press order, oldest first; the held direction is the last element.
    private var pressed: [Direction] = []

    public init() {}

    public var held: Direction? { pressed.last }

    public func press(_ direction: Direction) {
        pressed.removeAll { $0 == direction }
        pressed.append(direction)
    }

    public func release(_ direction: Direction) {
        pressed.removeAll { $0 == direction }
    }

    public func releaseAll() { pressed.removeAll() }

    /// Analog vector quantized to four directions with hysteresis (§6.3):
    /// the current direction is kept until another axis clearly dominates.
    public func updateFromAnalog(dx: Double, dy: Double, deadZone: Double) {
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude >= deadZone else {
            releaseAll()
            return
        }
        let dominanceRatio = 1.15
        let candidate: Direction
        if abs(dx) > abs(dy) * dominanceRatio {
            candidate = dx > 0 ? .right : .left
        } else if abs(dy) > abs(dx) * dominanceRatio {
            candidate = dy > 0 ? .down : .up
        } else if let current = held {
            candidate = current // inside the hysteresis band: keep direction
        } else {
            candidate = abs(dx) >= abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
        }
        if held != candidate {
            releaseAll()
            press(candidate)
        }
    }
}

#if canImport(GameController)
/// Hardware keyboard (arrows/WASD) and game-controller D-pad → held
/// direction. Uses GameController so the same path serves keyboards and
/// gamepads on iPhone, iPad, and macOS.
@MainActor
public final class PhysicalInputAdapter {
    private let store: HeldDirectionStore
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init(store: HeldDirectionStore) {
        self.store = store
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCControllerDidConnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rewire() }
            })
        }
        rewire()
    }

    /// (Re)wires every currently connected keyboard and controller. Input
    /// hot-plug stays outside authoritative simulation state (§17.4).
    private func rewire() {
        if let keyboard = GCKeyboard.coalesced { Self.wire(keyboard: keyboard, store: store) }
        for controller in GCController.controllers() { Self.wire(controller: controller, store: store) }
    }

    private static func wire(keyboard: GCKeyboard, store: HeldDirectionStore) {
        let bindings: [(GCKeyCode, Direction)] = [
            (.upArrow, .up), (.rightArrow, .right), (.downArrow, .down), (.leftArrow, .left),
            (.keyW, .up), (.keyD, .right), (.keyS, .down), (.keyA, .left),
        ]
        keyboard.keyboardInput?.keyChangedHandler = { _, _, keyCode, pressed in
            guard let direction = bindings.first(where: { $0.0 == keyCode })?.1 else { return }
            Task { @MainActor in
                pressed ? store.press(direction) : store.release(direction)
            }
        }
    }

    private static func wire(controller: GCController, store: HeldDirectionStore) {
        guard let pad = controller.extendedGamepad else { return }
        pad.dpad.valueChangedHandler = { dpad, x, y in
            Task { @MainActor in
                // D-pad y is up-positive; world is Y-down.
                store.updateFromAnalog(dx: Double(x), dy: Double(-y), deadZone: 0.5)
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
#endif
