import CoreGraphics
import SwiftUI

/// The stage HUD as icons (owner 2026-10-08: the bar was all text; show it
/// with icons, the way 决战坦克 and the genre do). GAME_RULES §15.2 lists
/// what it must show; every item is now the game's own art with a number
/// or a row of pips beside it — the player's and the enemies' tanks for the
/// counters, the base sprite in its damage state for the base, the pickup
/// icons for armour / power / speed / the weapon / the equipment — so the
/// HUD reads in the same language as the field and the chips need no
/// label. Numbers stay native monospaced text.
struct StageHUDBar: View {
    let hud: MovementLabController.HUDSnapshot
    /// Accessibility: 1.3 for the large HUD.
    var scale: CGFloat = 1
    @Environment(\.strings) private var strings

    private static let fire = Color(red: 1.0, green: 0.80, blue: 0.25)
    private static let empty = Color.white.opacity(0.22)

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 16) {
                // Reserve tanks, as the genre writes it: the tank and ×N.
                chip(MenuArt.tankIcon(kind: "player"), height: 15) {
                    Text(verbatim: "×\(hud.lives)").foregroundStyle(Color(red: 0.45, green: 0.95, blue: 0.85))
                }
                // Enemies: the number still to come, and a dot per tank on
                // the field (the field's cap is eight).
                chip(MenuArt.tankIcon(archetypeID: "normal_a"), height: 15) {
                    Text(verbatim: "\(hud.enemiesWaiting)").foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.35))
                    pips(hud.enemiesOnField, of: hud.enemiesOnField, colour: Color(red: 1.0, green: 0.4, blue: 0.3),
                         width: 4, height: 4, spacing: 2)
                }
                // The base in its own damage state, its shield over it, and
                // its durability as pips when it is a small number.
                chip(MenuArt.glyph(baseSprite), height: 16, overlay: hud.shield ? MenuArt.glyph("px_pickup_base_shield") : nil) {
                    if hud.baseMaxHP <= 8 {
                        pips(hud.baseHP, of: hud.baseMaxHP, colour: hud.baseHP > 1 ? Color(red: 0.4, green: 0.9, blue: 0.45) : .red)
                    } else {
                        Text(verbatim: "\(hud.baseHP)/\(hud.baseMaxHP)").foregroundStyle(hud.baseHP > 1 ? .green : .red)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(Self.fire)
                    Text(verbatim: "\(hud.score)").foregroundStyle(Self.fire)
                }
            }
            HStack(spacing: 16) {
                if hud.lifeState == .eliminated {
                    Text(strings("hud.eliminated")).foregroundStyle(.red)
                } else if hud.lifeState == .awaitingRespawn {
                    Text(strings("hud.respawning")).foregroundStyle(.cyan)
                } else {
                    chip(MenuArt.glyph("px_pickup_armor_up"), height: 14) {
                        pips(hud.armor, of: hud.maxArmor, colour: hud.armor > 1 ? Color(red: 0.35, green: 0.85, blue: 1.0) : .red)
                    }
                    // The special channel: its pickup icon and the rounds left.
                    // The rounds left, in the weapon's own colour (WeaponPalette).
                    chip(MenuArt.glyph("px_pickup_\(hud.weaponID)_weapon"), height: 14) {
                        let tint = WeaponPalette.tint(for: hud.weaponID).base
                        Text(verbatim: "\(hud.ammo)/\(hud.maxAmmo)")
                            .foregroundStyle(Color(red: tint.r, green: tint.g, blue: tint.b))
                    }
                    chip(MenuArt.glyph("px_pickup_power_up"), height: 14) {
                        pips(hud.powerLevel, of: 3, colour: .orange)
                    }
                    chip(MenuArt.glyph("px_pickup_speed_up"), height: 14) {
                        pips(hud.speedLevel, of: 3, colour: Self.fire)
                    }
                    // Equipment: the pickup it came from, or an empty slot.
                    if let id = hud.equipmentID, let icon = MenuArt.glyph("px_pickup_\(id)") {
                        chip(icon, height: 14) { EmptyView() }
                    } else {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(Self.empty, lineWidth: 1).frame(width: 14, height: 14)
                    }
                    if hud.invincible, let star = MenuArt.glyph("px_pickup_invincibility") {
                        chip(star, height: 14) { EmptyView() }
                            .shadow(color: Self.fire.opacity(0.9), radius: 3)
                    }
                }
            }
        }
        .font(.system(size: 12 * scale, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .scaleEffect(scale, anchor: .top)   // icons and pips grow with the text
    }

    private var baseSprite: String {
        guard hud.baseMaxHP > 0 else { return "px_base_healthy" }
        let ratio = Double(hud.baseHP) / Double(hud.baseMaxHP)
        if hud.baseHP <= 0 { return "px_base_destroyed" }
        if ratio > 2.0 / 3.0 { return "px_base_healthy" }
        if ratio > 1.0 / 3.0 { return "px_base_damaged" }
        return "px_base_critical"
    }

    /// An icon at a fixed height with its value beside it.
    @ViewBuilder private func chip<V: View>(_ icon: CGImage?, height: CGFloat, overlay: CGImage? = nil,
                                            @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(decorative: icon, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .overlay(alignment: .topTrailing) {
                        if let overlay {
                            Image(decorative: overlay, scale: 1)
                                .interpolation(.none).resizable().scaledToFit()
                                .frame(height: height * 0.6)
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            value()
        }
    }

    /// A row of pips: `value` lit of `total`.
    private func pips(_ value: Int, of total: Int, colour: Color,
                      width: CGFloat = 5, height: CGFloat = 9, spacing: CGFloat = 1.5) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(0, total), id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < value ? colour : Self.empty)
                    .frame(width: width, height: height)
            }
        }
    }
}
