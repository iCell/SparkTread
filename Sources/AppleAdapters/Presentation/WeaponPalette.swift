/// One colour per weapon (owner 2026-10-08: 每个子弹都应该有自己的颜色，通过
/// 这个颜色来渲染设计按钮). Taken from each round's own art — the normal
/// round's brass, the rapid rounds' lime, the flame, the AP shell's violet,
/// the demolition shell's orange — so a button, a HUD chip and the round on
/// the field say the same colour for the same gun. Plain components so both
/// SwiftUI and UIKit can wear them.
public enum WeaponPalette {
    public struct Tint: Equatable, Sendable {
        public let base: (r: Double, g: Double, b: Double)
        public let dark: (r: Double, g: Double, b: Double)
        public let light: (r: Double, g: Double, b: Double)

        public static func == (a: Tint, b: Tint) -> Bool { a.base == b.base && a.dark == b.dark && a.light == b.light }
    }

    public static func tint(for weaponID: String) -> Tint {
        switch weaponID {
        case "rapid": Tint(base: (0.58, 0.85, 0.24), dark: (0.26, 0.48, 0.10), light: (0.85, 0.98, 0.60))
        case "fire": Tint(base: (0.94, 0.33, 0.14), dark: (0.50, 0.12, 0.04), light: (1.00, 0.80, 0.40))
        case "ap": Tint(base: (0.62, 0.45, 0.90), dark: (0.28, 0.16, 0.48), light: (0.88, 0.80, 1.00))
        case "explosion": Tint(base: (0.95, 0.56, 0.16), dark: (0.50, 0.24, 0.04), light: (1.00, 0.85, 0.55))
        default: Tint(base: (0.96, 0.76, 0.24), dark: (0.52, 0.34, 0.06), light: (1.00, 0.94, 0.66))  // normal: brass
        }
    }
}
