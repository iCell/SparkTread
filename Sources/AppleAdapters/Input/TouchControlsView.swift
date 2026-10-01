#if canImport(UIKit)
import GameCore
import SwiftUI
import UIKit

/// Raw multi-touch gameplay controls (§17.4: gameplay touch input goes
/// through a UIKit hosting view, never SwiftUI gesture recognizers).
/// One floating stick on the left region plus two fire buttons; every touch
/// is tracked individually so stick + fire work simultaneously, and
/// `touchesCancelled` always releases state — no stuck directions.
/// A translucent glass disc, drawn rather than blurred.
///
/// `UIVisualEffectView` cannot sample the playfield behind it — SpriteKit
/// renders through Metal, and the material came out an opaque grey that hid
/// the bricks under the pad entirely (tried and rejected 2026-10-01). So the
/// glass is painted: a low-alpha channel tint the arena reads straight
/// through, a top-lit sheen over it, a bright rim, and one specular
/// highlight. Deterministic, and it looks the same over anything.
@MainActor private final class GlassDisc {
    private let tintLayer = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let rim = CAShapeLayer()
    private let gloss = CAShapeLayer()
    private let tint: UIColor
    private let restAlpha: CGFloat, pressedAlpha: CGFloat, restRim: CGFloat

    init(tint: UIColor, restAlpha: CGFloat, pressedAlpha: CGFloat, rim restRim: CGFloat) {
        self.tint = tint
        self.restAlpha = restAlpha
        self.pressedAlpha = pressedAlpha
        self.restRim = restRim
        tintLayer.fillColor = tint.withAlphaComponent(restAlpha).cgColor
        // Lit from the top, like a glass cap: strongest at the crown and
        // gone by the middle, so the lower half stays clear.
        sheen.colors = [UIColor.white.withAlphaComponent(0.30).cgColor,
                        UIColor.white.withAlphaComponent(0.05).cgColor,
                        UIColor.clear.cgColor]
        sheen.locations = [0, 0.42, 1]
        rim.fillColor = UIColor.clear.cgColor
        rim.lineWidth = 1.5
        rim.strokeColor = UIColor.white.withAlphaComponent(restRim).cgColor
        gloss.fillColor = UIColor.white.withAlphaComponent(0.28).cgColor
        gloss.strokeColor = UIColor.clear.cgColor
    }

    var isHidden: Bool = false {
        didSet { for l in layers { l.isHidden = isHidden } }
    }

    private var layers: [CALayer] { [tintLayer, sheen, rim, gloss] }

    func add(to parent: CALayer) { for l in layers { parent.addSublayer(l) } }

    func bringToFront(of parent: CALayer) { for l in layers { parent.addSublayer(l) } }

    func layout(center: CGPoint, radius: CGFloat) {
        let box = CGRect(x: center.x - radius, y: center.y - radius,
                         width: radius * 2, height: radius * 2)
        let circle = UIBezierPath(ovalIn: box).cgPath
        tintLayer.path = circle
        rim.path = circle
        sheen.frame = box
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: box.size)).cgPath
        sheen.mask = mask
        // The specular sits in the upper left, inset from the rim.
        gloss.path = UIBezierPath(ovalIn: CGRect(x: box.minX + radius * 0.30,
                                                 y: box.minY + radius * 0.20,
                                                 width: radius * 0.72,
                                                 height: radius * 0.40)).cgPath
    }

    func setPressed(_ pressed: Bool) {
        tintLayer.fillColor = tint.withAlphaComponent(pressed ? pressedAlpha : restAlpha).cgColor
        rim.strokeColor = UIColor.white.withAlphaComponent(pressed ? 0.85 : restRim).cgColor
        gloss.fillColor = UIColor.white.withAlphaComponent(pressed ? 0.42 : 0.28).cgColor
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

    /// Glass controls (owner 2026-10-01: 操控面板还是用透明的有玻璃效果的
    /// 背景). The delivery's opaque `PixelUI` discs were wired up earlier the
    /// same day and covered the arena under the pad; these let it through.
    /// The channel tints — cyan for the normal gun, orange for the special —
    /// match the HUD's own colour coding.
    private let stickBase = GlassDisc(tint: .white, restAlpha: 0.10, pressedAlpha: 0.10, rim: 0.30)
    private let stickKnob = GlassDisc(tint: .white, restAlpha: 0.26, pressedAlpha: 0.26, rim: 0.62)
    private let normalDisc = GlassDisc(tint: .systemCyan, restAlpha: 0.18, pressedAlpha: 0.40, rim: 0.48)
    private let specialDisc = GlassDisc(tint: .systemOrange, restAlpha: 0.18, pressedAlpha: 0.40, rim: 0.48)
    private let normalLabel = UILabel()
    private let specialLabel = UILabel()
    private let normalIcon = UIImageView()
    private let specialIcon = UIImageView()
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

        for disc in [normalDisc, specialDisc, stickBase, stickKnob] { disc.add(to: layer) }
        // The floating stick stays hidden until it is touched.
        stickBase.isHidden = true
        stickKnob.isHidden = true

        configureCaption(normalLabel, text: "普")
        configureCaption(specialLabel, text: "特")
        for icon in [normalIcon, specialIcon] {
            icon.contentMode = .scaleAspectFit
            icon.layer.magnificationFilter = .nearest
            addSubview(icon)
        }
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

    /// Shows the weapon icons; the text labels remain only as a fallback
    /// when the art is not loaded yet.
    func updateIcons(specialWeaponID: String) {
        guard let iconProvider else { return }
        if normalIcon.image == nil, let image = iconProvider("normal") {
            normalIcon.image = UIImage(cgImage: image)
            normalLabel.isHidden = true
        }
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
        for (label, icon, center) in [(normalLabel, normalIcon, normalCenter),
                                      (specialLabel, specialIcon, specialCenter)] {
            label.frame = CGRect(x: center.x - buttonRadius, y: center.y - buttonRadius,
                                 width: buttonRadius * 2, height: buttonRadius * 2)
            icon.frame = label.frame.insetBy(dx: 12, dy: 12)
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
                stickBase.isHidden = false
                stickKnob.isHidden = false
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
                stickBase.isHidden = true
                stickKnob.isHidden = true
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
            uiView.iconProvider = { weaponID in
                try? art.texture("px_projectile_" + weaponID).cgImage()
            }
        }
        uiView.updateIcons(specialWeaponID: specialWeaponID)
    }
}
#endif
