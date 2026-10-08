#if canImport(UIKit)
import GameCore
import SwiftUI
import UIKit

/// Raw multi-touch gameplay controls (§17.4: gameplay touch input goes
/// through a UIKit hosting view, never SwiftUI gesture recognizers).
/// One floating stick on the left region plus two fire buttons; every touch
/// is tracked individually so stick + fire work simultaneously, and
/// `touchesCancelled` always releases state — no stuck directions.
/// A control disc in the menus' plate language (owner 2026-10-06/08: the
/// stick and the fire buttons were ugly): a ring of the arena's steel —
/// fire yellow for the special channel — around dark glass the field
/// still shows through, a top sheen inside the ring, and a press that
/// fills the glass with the channel's colour. Painted in layers, not
/// blurred: `UIVisualEffectView` cannot sample SpriteKit's Metal surface
/// (tried and rejected 2026-10-01).
@MainActor private final class ControlDisc {
    private let glass = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let ring = CAShapeLayer()
    private let innerLine = CAShapeLayer()
    private var ringColour: UIColor, pressedFill: UIColor
    private var restFill: UIColor
    private let ringWidth: CGFloat

    init(ring ringColour: UIColor, pressedFill: UIColor, glassAlpha: CGFloat = 0.32, ringWidth: CGFloat = 3) {
        self.ringColour = ringColour
        self.pressedFill = pressedFill
        self.restFill = UIColor.black.withAlphaComponent(glassAlpha)
        self.ringWidth = ringWidth
        glass.fillColor = restFill.cgColor
        sheen.colors = [UIColor.white.withAlphaComponent(0.22).cgColor,
                        UIColor.white.withAlphaComponent(0.04).cgColor,
                        UIColor.clear.cgColor]
        sheen.locations = [0, 0.45, 1]
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = ringWidth
        ring.strokeColor = ringColour.cgColor
        innerLine.fillColor = UIColor.clear.cgColor
        innerLine.lineWidth = 1
        innerLine.strokeColor = UIColor.black.withAlphaComponent(0.55).cgColor
    }

    var isHidden: Bool = false {
        didSet { for l in layers { l.isHidden = isHidden } }
    }

    private var layers: [CALayer] { [glass, sheen, innerLine, ring] }

    func add(to parent: CALayer) { for l in layers { parent.addSublayer(l) } }

    func layout(center: CGPoint, radius: CGFloat) {
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        glass.path = UIBezierPath(ovalIn: box).cgPath
        ring.path = UIBezierPath(ovalIn: box.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)).cgPath
        innerLine.path = UIBezierPath(ovalIn: box.insetBy(dx: ringWidth + 0.5, dy: ringWidth + 0.5)).cgPath
        sheen.frame = box
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: box.size).insetBy(dx: ringWidth, dy: ringWidth)).cgPath
        sheen.mask = mask
    }

    func setPressed(_ pressed: Bool) {
        glass.fillColor = pressed ? pressedFill.cgColor : restFill.cgColor
        ring.strokeColor = pressed ? UIColor.white.cgColor : ringColour.cgColor
    }

    /// Re-skins the disc as a weapon's colour: the glass itself is the
    /// colour at rest (the field reads through it), deeper when pressed,
    /// the ring the colour at full strength.
    func setTint(_ colour: UIColor) {
        ringColour = colour.withAlphaComponent(0.95)
        restFill = colour.withAlphaComponent(0.30)
        pressedFill = colour.withAlphaComponent(0.62)
        ring.strokeColor = ringColour.cgColor
        glass.fillColor = restFill.cgColor
    }
}

final class TouchControlsUIView: UIView {
    weak var store: HeldDirectionStore?
    var onNormalFire: ((Bool) -> Void)?
    var onSpecialFire: ((Bool) -> Void)?

    private var stickTouch: UITouch?
    private var stickOrigin: CGPoint = .zero
    private var normalTouch: UITouch?
    private var specialTouch: UITouch?

    /// Controls over glass (owner 2026-10-01: the pad must stay see-through;
    /// 2026-10-08: each round has its own colour, and the button IS that
    /// colour — tinted glass with a ring, no glyph in the middle). The
    /// stick is steel; a fire button's glass and ring are its weapon's
    /// colour (`WeaponPalette`), so the normal gun is brass and the special
    /// button changes colour with the weapon.
    private static let steel = UIColor(red: 0.62, green: 0.68, blue: 0.73, alpha: 0.95)
    static func colour(_ c: (r: Double, g: Double, b: Double), alpha: CGFloat = 1) -> UIColor {
        UIColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
    private let stickBase = ControlDisc(ring: TouchControlsUIView.steel.withAlphaComponent(0.7),
                                        pressedFill: .clear, glassAlpha: 0.22, ringWidth: 2.5)
    private let stickKnob = ControlDisc(ring: TouchControlsUIView.steel, pressedFill: .clear, glassAlpha: 0.45, ringWidth: 2)
    private let normalDisc = ControlDisc(ring: TouchControlsUIView.steel, pressedFill: .clear)
    private let specialDisc = ControlDisc(ring: TouchControlsUIView.steel, pressedFill: .clear)
    /// The four arrow glyphs on the stick's base; the held direction lights.
    private let arrowLayers: [Direction: CALayer] = [.up: CALayer(), .right: CALayer(), .down: CALayer(), .left: CALayer()]
    var arrowProvider: ((Direction) -> CGImage?)?
    private var shownSpecialWeapon: String?

    /// Visible 66 pt buttons; 45 pt hit radius (90 pt circles) whose centres
    /// sit 96 pt apart so the two hit areas never overlap (§15.2).
    private let buttonRadius: CGFloat = 33
    private let hitPadding: CGFloat = 12
    private var normalCenter: CGPoint = .zero
    private var specialCenter: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear

        stickBase.add(to: layer)
        for direction in Direction.allCases {
            let arrow = arrowLayers[direction]!
            arrow.magnificationFilter = .nearest
            arrow.contentsGravity = .resizeAspect
            arrow.opacity = 0.55
            arrow.isHidden = true
            layer.addSublayer(arrow)
        }
        for disc in [stickKnob, normalDisc, specialDisc] { disc.add(to: layer) }
        // The floating stick stays hidden until it is touched.
        setStickHidden(true)

        normalDisc.setTint(Self.colour(WeaponPalette.tint(for: "normal").base))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setStickHidden(_ hidden: Bool) {
        stickBase.isHidden = hidden
        stickKnob.isHidden = hidden
        for arrow in arrowLayers.values { arrow.isHidden = hidden }
    }

    /// Loads the stick's arrows once, and re-skins the special button
    /// whenever the special weapon changes.
    func updateWeapons(specialWeaponID: String) {
        if let arrowProvider {
            for direction in Direction.allCases where arrowLayers[direction]?.contents == nil {
                if let image = arrowProvider(direction) { arrowLayers[direction]?.contents = image }
            }
        }
        guard shownSpecialWeapon != specialWeaponID else { return }
        shownSpecialWeapon = specialWeaponID
        specialDisc.setTint(Self.colour(WeaponPalette.tint(for: specialWeaponID).base))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = safeAreaInsets
        // The arcade pair (owner 2026-10-08, from a reference shot): the
        // main button low and inward under the thumb, the second up and
        // out on the diagonal — not stacked. Centres 98 pt across and 58 pt
        // up, 114 pt apart, so the 90 pt hit circles still never overlap
        // (§15.2 wants ≥ 96).
        specialCenter = CGPoint(x: bounds.width - inset.right - 24 - buttonRadius,
                                y: bounds.height - inset.bottom - 16 - buttonRadius - 58)
        normalCenter = CGPoint(x: specialCenter.x - 98, y: specialCenter.y + 58)
        normalDisc.layout(center: normalCenter, radius: buttonRadius)
        specialDisc.layout(center: specialCenter, radius: buttonRadius)
    }

    private func buttonHit(_ point: CGPoint, center: CGPoint) -> Bool {
        // Touch target padded past the visible art (≥44pt rule, §17.3).
        let dx = point.x - center.x, dy = point.y - center.y
        return dx * dx + dy * dy <= (buttonRadius + hitPadding) * (buttonRadius + hitPadding)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if normalTouch == nil, buttonHit(point, center: normalCenter) {
                normalTouch = touch
                normalDisc.setPressed(true)
                onNormalFire?(true)
            } else if specialTouch == nil, buttonHit(point, center: specialCenter) {
                specialTouch = touch
                specialDisc.setPressed(true)
                onSpecialFire?(true)
            } else if stickTouch == nil, point.x < bounds.width * 0.62 {
                stickTouch = touch
                stickOrigin = point
                updateStickVisual(offset: .zero)
                setStickHidden(false)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let stickTouch, touches.contains(stickTouch) else { return }
        let point = stickTouch.location(in: self)
        var dx = point.x - stickOrigin.x, dy = point.y - stickOrigin.y
        // Leashed origin: past the stick radius the origin follows the
        // finger, so reversing direction responds immediately instead of
        // requiring a drag back across the original touch-down point.
        let magnitude = (dx * dx + dy * dy).squareRoot()
        let leash: CGFloat = 36
        if magnitude > leash {
            let excess = magnitude - leash
            stickOrigin.x += dx / magnitude * excess
            stickOrigin.y += dy / magnitude * excess
            dx = point.x - stickOrigin.x
            dy = point.y - stickOrigin.y
        }
        store?.updateFromAnalog(dx: dx, dy: dy, deadZone: 12, from: .touch)
        updateStickVisual(offset: CGPoint(x: dx, y: dy))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches) // the guarantee SwiftUI gestures could not give
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch == stickTouch {
                stickTouch = nil
                store?.release(from: .touch)
                setStickHidden(true)
            }
            if touch == normalTouch {
                normalTouch = nil
                normalDisc.setPressed(false)
                onNormalFire?(false)
            }
            if touch == specialTouch {
                specialTouch = nil
                specialDisc.setPressed(false)
                onSpecialFire?(false)
            }
        }
    }

    private func updateStickVisual(offset: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let clampedX = max(-34, min(34, offset.x)), clampedY = max(-34, min(34, offset.y))
        // Same 96 pt base, 44 pt thumb and ±34 pt clamp the vector stick used.
        stickBase.layout(center: stickOrigin, radius: 48)
        stickKnob.layout(center: CGPoint(x: stickOrigin.x + clampedX, y: stickOrigin.y + clampedY),
                         radius: 22)
        // Arrows just inside the ring; the held direction (the same reading
        // as the store's: the larger axis past the dead zone) lights up.
        let held: Direction? = (abs(offset.x) < 12 && abs(offset.y) < 12) ? nil
            : abs(offset.x) >= abs(offset.y) ? (offset.x > 0 ? .right : .left) : (offset.y > 0 ? .down : .up)
        for (direction, arrow) in arrowLayers {
            let v = direction.vector
            let at = CGPoint(x: stickOrigin.x + CGFloat(v.x) * 34, y: stickOrigin.y + CGFloat(v.y) * 34)
            arrow.frame = CGRect(x: at.x - 8, y: at.y - 8, width: 16, height: 16)
            arrow.opacity = direction == held ? 1.0 : 0.45
        }
        CATransaction.commit()
    }
}

struct TouchControlsView: UIViewRepresentable {
    let controller: MovementLabController
    var art: PixelArt?
    var specialWeaponID: String = "rapid"

    func makeUIView(context: Context) -> TouchControlsUIView {
        let view = TouchControlsUIView(frame: .zero)
        let store = controller.input
        view.store = store
        view.onNormalFire = { pressed in
            pressed ? store.pressNormalFire(from: .touch) : store.releaseNormalFire(from: .touch)
        }
        view.onSpecialFire = { held in
            held ? store.pressSpecialFire(from: .touch) : store.releaseSpecialFire(from: .touch)
        }
        return view
    }

    func updateUIView(_ uiView: TouchControlsUIView, context: Context) {
        if let art {
            // The stick wears the delivery's own arrow glyphs; the fire
            // buttons are drawn in their weapons' colours (§15.2: icons, not
            // 普/特).
            _ = art
            uiView.arrowProvider = { direction in
                let name = switch direction { case .up: "up"; case .right: "right"; case .down: "down"; case .left: "left" }
                return MenuArt.glyph("px_ui_icon_\(name)")
            }
        }
        uiView.updateWeapons(specialWeaponID: specialWeaponID)
    }
}
#endif
