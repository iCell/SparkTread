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
    private let ringColour: UIColor, pressedFill: UIColor
    private let restGlass: CGFloat, ringWidth: CGFloat

    init(ring ringColour: UIColor, pressedFill: UIColor, glassAlpha: CGFloat = 0.32, ringWidth: CGFloat = 3) {
        self.ringColour = ringColour
        self.pressedFill = pressedFill
        self.restGlass = glassAlpha
        self.ringWidth = ringWidth
        glass.fillColor = UIColor.black.withAlphaComponent(glassAlpha).cgColor
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
        glass.fillColor = pressed ? pressedFill.cgColor : UIColor.black.withAlphaComponent(restGlass).cgColor
        ring.strokeColor = pressed ? UIColor.white.cgColor : ringColour.cgColor
    }
}

/// A brass shell in vectors for the normal fire button (see
/// `TouchControlsUIView.normalShell`).
@MainActor private final class NormalShellGlyph {
    private let rim = CAShapeLayer()
    private let body = CAShapeLayer()
    private let band = CAShapeLayer()
    private let highlight = CAShapeLayer()

    init() {
        rim.fillColor = UIColor(red: 0.16, green: 0.10, blue: 0.03, alpha: 1).cgColor
        body.fillColor = UIColor(red: 0.93, green: 0.70, blue: 0.22, alpha: 1).cgColor
        band.fillColor = UIColor(red: 0.62, green: 0.40, blue: 0.10, alpha: 1).cgColor
        highlight.fillColor = UIColor(red: 1.0, green: 0.93, blue: 0.65, alpha: 0.9).cgColor
    }

    func add(to parent: CALayer) { for l in [rim, body, band, highlight] { parent.addSublayer(l) } }

    /// A shell `height` tall: a round tip over a straight body, a darker
    /// band at the base, a light stripe up the left; the rim is the same
    /// shape grown by 2 pt.
    func layout(center: CGPoint, height: CGFloat) {
        let width = height * 0.46
        let box = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        func shell(_ r: CGRect) -> CGPath {
            // An ogive: the sides sweep into a point over the top 45 %.
            let path = UIBezierPath()
            let shoulder = r.minY + r.height * 0.45
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: shoulder))
            path.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY),
                              controlPoint: CGPoint(x: r.minX, y: r.minY + r.height * 0.12))
            path.addQuadCurve(to: CGPoint(x: r.maxX, y: shoulder),
                              controlPoint: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.close()
            return path.cgPath
        }
        rim.path = shell(box.insetBy(dx: -2, dy: -2))
        body.path = shell(box)
        band.path = UIBezierPath(rect: CGRect(x: box.minX, y: box.maxY - height * 0.2, width: width, height: height * 0.2)).cgPath
        highlight.path = UIBezierPath(roundedRect: CGRect(x: box.minX + width * 0.18, y: box.minY + height * 0.22,
                                                          width: width * 0.16, height: height * 0.5),
                                      cornerRadius: width * 0.08).cgPath
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

    /// Plate-language controls over glass (owner 2026-10-01: the pad must
    /// stay see-through; 2026-10-08: the glass alone looked ugly). Steel for
    /// the stick and the normal gun, fire yellow for the special channel —
    /// the same two materials as every plate in the menus.
    private static let steel = UIColor(red: 0.62, green: 0.68, blue: 0.73, alpha: 0.95)
    private static let fire = UIColor(red: 1.0, green: 0.80, blue: 0.25, alpha: 0.95)
    private let stickBase = ControlDisc(ring: TouchControlsUIView.steel.withAlphaComponent(0.7),
                                        pressedFill: .clear, glassAlpha: 0.22, ringWidth: 2.5)
    private let stickKnob = ControlDisc(ring: TouchControlsUIView.steel, pressedFill: .clear, glassAlpha: 0.45, ringWidth: 2)
    private let normalDisc = ControlDisc(ring: TouchControlsUIView.steel,
                                         pressedFill: UIColor.white.withAlphaComponent(0.38))
    private let specialDisc = ControlDisc(ring: TouchControlsUIView.fire,
                                          pressedFill: TouchControlsUIView.fire.withAlphaComponent(0.45))
    /// The four arrow glyphs on the stick's base; the held direction lights.
    private let arrowLayers: [Direction: CALayer] = [.up: CALayer(), .right: CALayer(), .down: CALayer(), .left: CALayer()]
    var arrowProvider: ((Direction) -> CGImage?)?
    private let normalLabel = UILabel()
    private let specialLabel = UILabel()
    private let normalIcon = UIImageView()
    private let specialIcon = UIImageView()
    /// The normal gun's face is drawn, not sampled: its projectile art is
    /// 3×8 px and blurred into blocks at button size (owner 2026-10-08), so
    /// the button shows a brass shell in vectors — tip, body, base band,
    /// a highlight — in the round's own gold, with a dark rim like a plate.
    private let normalShell = NormalShellGlyph()
    /// Weapon icons (GAME_RULES §15.2): the normal round and the current
    /// special weapon's projectile art replace text placeholders.
    var iconProvider: ((String) -> CGImage?)?
    private var shownSpecialWeapon: String?

    /// Visible 66 pt buttons; 45 pt hit radius (90 pt circles) whose centres
    /// sit 96 pt apart so the two hit areas never overlap (§15.2).
    private let buttonRadius: CGFloat = 33
    private let hitPadding: CGFloat = 12
    private let buttonGap: CGFloat = 30
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

        configureCaption(normalLabel, text: "普")
        configureCaption(specialLabel, text: "特")
        for icon in [normalIcon, specialIcon] {
            icon.contentMode = .scaleAspectFit
            icon.layer.magnificationFilter = .nearest
            addSubview(icon)
        }
        normalShell.add(to: layer)
        normalLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureCaption(_ label: UILabel, text: String) {
        label.text = text
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        addSubview(label)
    }

    private func setStickHidden(_ hidden: Bool) {
        stickBase.isHidden = hidden
        stickKnob.isHidden = hidden
        for arrow in arrowLayers.values { arrow.isHidden = hidden }
    }

    /// Shows the weapon icons; the text labels remain only as a fallback
    /// when the art is not loaded yet.
    func updateIcons(specialWeaponID: String) {
        if let arrowProvider {
            for direction in Direction.allCases where arrowLayers[direction]?.contents == nil {
                if let image = arrowProvider(direction) { arrowLayers[direction]?.contents = image }
            }
        }
        guard let iconProvider else { return }
        guard shownSpecialWeapon != specialWeaponID, let image = iconProvider(specialWeaponID) else { return }
        shownSpecialWeapon = specialWeaponID
        specialIcon.image = UIImage(cgImage: image)
        specialLabel.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = safeAreaInsets
        normalCenter = CGPoint(x: bounds.width - inset.right - 24 - buttonRadius,
                               y: bounds.height - inset.bottom - 16 - buttonRadius)
        specialCenter = CGPoint(x: normalCenter.x, y: normalCenter.y - buttonRadius * 2 - buttonGap)
        normalDisc.layout(center: normalCenter, radius: buttonRadius)
        specialDisc.layout(center: specialCenter, radius: buttonRadius)
        normalShell.layout(center: normalCenter, height: 34)
        for (label, icon, center) in [(normalLabel, normalIcon, normalCenter),
                                      (specialLabel, specialIcon, specialCenter)] {
            label.frame = CGRect(x: center.x - buttonRadius, y: center.y - buttonRadius,
                                 width: buttonRadius * 2, height: buttonRadius * 2)
            icon.frame = label.frame.insetBy(dx: 15, dy: 15)
        }
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
            // The fire buttons wear the weapon pickups' icons (§15.2: an
            // icon, not 普/特), cropped to their art; the stick wears the
            // delivery's own arrow glyphs.
            uiView.iconProvider = { weaponID in
                MenuArt.glyph(weaponID == "normal" ? "px_projectile_normal" : "px_pickup_\(weaponID)_weapon")
            }
            uiView.arrowProvider = { direction in
                let name = switch direction { case .up: "up"; case .right: "right"; case .down: "down"; case .left: "left" }
                return MenuArt.glyph("px_ui_icon_\(name)")
            }
        }
        uiView.updateIcons(specialWeaponID: specialWeaponID)
    }
}
#endif
