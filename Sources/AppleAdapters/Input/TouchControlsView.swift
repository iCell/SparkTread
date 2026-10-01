#if canImport(UIKit)
import GameCore
import SwiftUI
import UIKit

/// Raw multi-touch gameplay controls (§17.4: gameplay touch input goes
/// through a UIKit hosting view, never SwiftUI gesture recognizers).
/// One floating stick on the left region plus two fire buttons; every touch
/// is tracked individually so stick + fire work simultaneously, and
/// `touchesCancelled` always releases state — no stuck directions.
final class TouchControlsUIView: UIView {
    weak var store: HeldDirectionStore?
    var onNormalFire: ((Bool) -> Void)?
    var onSpecialFire: ((Bool) -> Void)?

    private var stickTouch: UITouch?
    private var stickOrigin: CGPoint = .zero
    private var normalTouch: UITouch?
    private var specialTouch: UITouch?

    // The shape layers are the fallback the controls draw themselves with
    // until the delivery's own control art is available (and if it never
    // is): the view must stay usable without `PixelArt`.
    private let ringLayer = CAShapeLayer()
    private let knobLayer = CAShapeLayer()
    private let normalButton = CAShapeLayer()
    private let specialButton = CAShapeLayer()
    private let normalLabel = UILabel()
    private let specialLabel = UILabel()
    private let normalIcon = UIImageView()
    private let specialIcon = UIImageView()
    /// The delivery's control art (`PixelUI`, wired up 2026-10-01): the
    /// stick base, its thumb and the two fire buttons, which until now were
    /// plain vector circles while this art sat unused in the bundle. The hit
    /// geometry of §15.2 is unchanged — only what is drawn changed.
    private let stickBase = UIImageView()
    private let stickKnob = UIImageView()
    private let normalArt = UIImageView()
    private let specialArt = UIImageView()
    private var stickRestImage: UIImage?
    private var stickPressedImage: UIImage?
    private var artLoaded = false
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

        ringLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 2
        ringLayer.isHidden = true
        knobLayer.fillColor = UIColor.white.withAlphaComponent(0.45).cgColor
        knobLayer.isHidden = true
        layer.addSublayer(ringLayer)
        layer.addSublayer(knobLayer)

        configureButton(normalButton, label: normalLabel, text: "普", color: .systemCyan)
        configureButton(specialButton, label: specialLabel, text: "特", color: .systemOrange)
        // The art sits over the fallback shapes and under the weapon icons.
        for art in [stickBase, stickKnob, normalArt, specialArt] {
            art.contentMode = .scaleAspectFit
            art.layer.magnificationFilter = .nearest
            art.isHidden = true
            addSubview(art)
        }
        for icon in [normalIcon, specialIcon] {
            icon.contentMode = .scaleAspectFit
            icon.layer.magnificationFilter = .nearest
            addSubview(icon)
        }
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

    /// Takes the control art once it can be loaded and retires the vector
    /// fallback. Idempotent: `updateUIView` runs on every SwiftUI pass.
    func updateControlArt(_ provider: (String) -> CGImage?) {
        guard !artLoaded,
              let base = provider("px_ui_joystick_normal"),
              let knob = provider("px_ui_control_knob"),
              let normal = provider("px_ui_control_normal"),
              let special = provider("px_ui_control_special") else { return }
        stickRestImage = UIImage(cgImage: base)
        stickPressedImage = provider("px_ui_joystick_pressed").map(UIImage.init(cgImage:)) ?? stickRestImage
        stickBase.image = stickRestImage
        stickKnob.image = UIImage(cgImage: knob)
        normalArt.image = UIImage(cgImage: normal)
        specialArt.image = UIImage(cgImage: special)
        artLoaded = true
        // The fire buttons are always on screen; the stick is a floating
        // control and stays hidden until touched, exactly as the ring and
        // knob it replaces did.
        normalButton.isHidden = true
        specialButton.isHidden = true
        normalArt.isHidden = false
        specialArt.isHidden = false
        setNeedsLayout()
    }

    /// Pixel art has no round pressed variant in this set, so a press reads
    /// as the button coming fully opaque and sinking slightly.
    private func setPressed(_ pressed: Bool, art: UIImageView, icon: UIImageView) {
        guard artLoaded else { return }
        let scale: CGFloat = pressed ? 0.93 : 1.0
        art.transform = CGAffineTransform(scaleX: scale, y: scale)
        icon.transform = art.transform
        art.alpha = pressed ? 1.0 : 0.88
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureButton(_ shape: CAShapeLayer, label: UILabel, text: String, color: UIColor) {
        shape.fillColor = color.withAlphaComponent(0.4).cgColor
        shape.strokeColor = color.withAlphaComponent(0.9).cgColor
        shape.lineWidth = 2
        layer.addSublayer(shape)
        label.text = text
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = safeAreaInsets
        normalCenter = CGPoint(x: bounds.width - inset.right - 24 - buttonRadius,
                               y: bounds.height - inset.bottom - 16 - buttonRadius)
        specialCenter = CGPoint(x: normalCenter.x, y: normalCenter.y - buttonRadius * 2 - buttonGap)
        for (shape, label, icon, center) in [(normalButton, normalLabel, normalIcon, normalCenter),
                                             (specialButton, specialLabel, specialIcon, specialCenter)] {
            shape.path = UIBezierPath(arcCenter: center, radius: buttonRadius,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            label.frame = CGRect(x: center.x - buttonRadius, y: center.y - buttonRadius,
                                 width: buttonRadius * 2, height: buttonRadius * 2)
            icon.frame = label.frame.insetBy(dx: 12, dy: 12)
        }
        // The art fills the same 66 pt circle the vector button described.
        normalArt.frame = CGRect(x: normalCenter.x - buttonRadius, y: normalCenter.y - buttonRadius,
                                 width: buttonRadius * 2, height: buttonRadius * 2)
        specialArt.frame = CGRect(x: specialCenter.x - buttonRadius, y: specialCenter.y - buttonRadius,
                                  width: buttonRadius * 2, height: buttonRadius * 2)
        if artLoaded {
            normalArt.alpha = normalTouch == nil ? 0.88 : 1.0
            specialArt.alpha = specialTouch == nil ? 0.88 : 1.0
        }
        bringSubviewToFront(normalIcon)
        bringSubviewToFront(specialIcon)
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
                normalButton.fillColor = UIColor.systemCyan.withAlphaComponent(0.75).cgColor
                setPressed(true, art: normalArt, icon: normalIcon)
                onNormalFire?(true)
            } else if specialTouch == nil, buttonHit(point, center: specialCenter) {
                specialTouch = touch
                specialButton.fillColor = UIColor.systemOrange.withAlphaComponent(0.75).cgColor
                setPressed(true, art: specialArt, icon: specialIcon)
                onSpecialFire?(true)
            } else if stickTouch == nil, point.x < bounds.width * 0.62 {
                stickTouch = touch
                stickOrigin = point
                updateStickVisual(offset: .zero)
                ringLayer.isHidden = artLoaded
                knobLayer.isHidden = artLoaded
                stickBase.isHidden = !artLoaded
                stickKnob.isHidden = !artLoaded
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
                ringLayer.isHidden = true
                knobLayer.isHidden = true
                stickBase.isHidden = true
                stickKnob.isHidden = true
            }
            if touch == normalTouch {
                normalTouch = nil
                normalButton.fillColor = UIColor.systemCyan.withAlphaComponent(0.4).cgColor
                setPressed(false, art: normalArt, icon: normalIcon)
                onNormalFire?(false)
            }
            if touch == specialTouch {
                specialTouch = nil
                specialButton.fillColor = UIColor.systemOrange.withAlphaComponent(0.4).cgColor
                setPressed(false, art: specialArt, icon: specialIcon)
                onSpecialFire?(false)
            }
        }
    }

    private func updateStickVisual(offset: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.path = UIBezierPath(arcCenter: stickOrigin, radius: 48,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        let clampedX = max(-34, min(34, offset.x)), clampedY = max(-34, min(34, offset.y))
        let knobCenter = CGPoint(x: stickOrigin.x + clampedX, y: stickOrigin.y + clampedY)
        knobLayer.path = UIBezierPath(arcCenter: knobCenter, radius: 22,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        if artLoaded {
            // The 48 px base and thumb are drawn at whole multiples — 96 pt
            // and 48 pt — so the pixels stay square, and they sit on the
            // same centres and the same ±34 pt clamp as the vector stick.
            stickBase.frame = CGRect(x: stickOrigin.x - 48, y: stickOrigin.y - 48, width: 96, height: 96)
            stickKnob.frame = CGRect(x: knobCenter.x - 24, y: knobCenter.y - 24, width: 48, height: 48)
            let moved = abs(clampedX) + abs(clampedY) > 1
            stickBase.image = moved ? stickPressedImage : stickRestImage
            bringSubviewToFront(stickBase)
            bringSubviewToFront(stickKnob)
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
            uiView.iconProvider = { weaponID in
                try? art.texture("px_projectile_" + weaponID).cgImage()
            }
            uiView.updateControlArt { try? art.texture($0).cgImage() }
        }
        uiView.updateIcons(specialWeaponID: specialWeaponID)
    }
}
#endif
