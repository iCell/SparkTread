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

    private let ringLayer = CAShapeLayer()
    private let knobLayer = CAShapeLayer()
    private let normalButton = CAShapeLayer()
    private let specialButton = CAShapeLayer()
    private let normalLabel = UILabel()
    private let specialLabel = UILabel()

    private let buttonRadius: CGFloat = 33
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
        specialCenter = CGPoint(x: normalCenter.x, y: normalCenter.y - buttonRadius * 2 - 18)
        for (shape, label, center) in [(normalButton, normalLabel, normalCenter),
                                       (specialButton, specialLabel, specialCenter)] {
            shape.path = UIBezierPath(arcCenter: center, radius: buttonRadius,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            label.frame = CGRect(x: center.x - buttonRadius, y: center.y - buttonRadius,
                                 width: buttonRadius * 2, height: buttonRadius * 2)
        }
    }

    private func buttonHit(_ point: CGPoint, center: CGPoint) -> Bool {
        // Touch target padded past the visible art (≥44pt rule, §17.3).
        let dx = point.x - center.x, dy = point.y - center.y
        return dx * dx + dy * dy <= (buttonRadius + 12) * (buttonRadius + 12)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if normalTouch == nil, buttonHit(point, center: normalCenter) {
                normalTouch = touch
                normalButton.fillColor = UIColor.systemCyan.withAlphaComponent(0.75).cgColor
                onNormalFire?(true)
            } else if specialTouch == nil, buttonHit(point, center: specialCenter) {
                specialTouch = touch
                specialButton.fillColor = UIColor.systemOrange.withAlphaComponent(0.75).cgColor
                onSpecialFire?(true)
            } else if stickTouch == nil, point.x < bounds.width * 0.62 {
                stickTouch = touch
                stickOrigin = point
                updateStickVisual(offset: .zero)
                ringLayer.isHidden = false
                knobLayer.isHidden = false
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
        store?.updateFromAnalog(dx: dx, dy: dy, deadZone: 12)
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
                store?.releaseAll()
                ringLayer.isHidden = true
                knobLayer.isHidden = true
            }
            if touch == normalTouch {
                normalTouch = nil
                normalButton.fillColor = UIColor.systemCyan.withAlphaComponent(0.4).cgColor
                onNormalFire?(false)
            }
            if touch == specialTouch {
                specialTouch = nil
                specialButton.fillColor = UIColor.systemOrange.withAlphaComponent(0.4).cgColor
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
        knobLayer.path = UIBezierPath(
            arcCenter: CGPoint(x: stickOrigin.x + clampedX, y: stickOrigin.y + clampedY),
            radius: 22, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        CATransaction.commit()
    }
}

struct TouchControlsView: UIViewRepresentable {
    let controller: MovementLabController

    func makeUIView(context: Context) -> TouchControlsUIView {
        let view = TouchControlsUIView(frame: .zero)
        view.store = controller.input
        view.onNormalFire = { [weak controller] held in controller?.normalFireHeld = held }
        view.onSpecialFire = { [weak controller] held in controller?.specialFireHeld = held }
        return view
    }

    func updateUIView(_ uiView: TouchControlsUIView, context: Context) {}
}
#endif
