import GameCore

/// Canonical difficulty schema (`Content/difficulties/*.json`, plan §10.7
/// "Exact numbers live in DifficultyDefinition"; ADR-0005 `allied_base_damage`;
/// ADR-0015). Composition variants: `forgiving` swaps C/D archetype tiers
/// for A/B, `baseline` keeps the authored composition, `advanced` promotes
/// every third A/B entry to its C/D tier.
public struct DifficultyDefinition: Codable, Equatable, Sendable {
    public enum CompositionVariant: String, Codable, Sendable, CaseIterable {
        case forgiving, baseline, advanced
    }

    public var schemaVersion: Int
    public var id: String
    public var displayNameKey: String
    public var enemyBehavior: EnemyBehaviorProfile
    /// Percent scale on the stage's telegraph duration; never below the
    /// 45-tick fairness floor (§10.6).
    public var telegraphTicksPercent: Int
    public var composition: CompositionVariant
    /// ADR-0005: whether the player's own fire hurts the base.
    public var alliedBaseDamage: Bool
    /// Plan §10.7 "enemy special ammo %": recorded for the header and the
    /// description; enemies are ammunition-exempt (§6.4), so it has no
    /// simulation effect yet.
    public var enemySpecialAmmoPercent: Int

    public init(schemaVersion: Int = 1, id: String, displayNameKey: String,
                enemyBehavior: EnemyBehaviorProfile, telegraphTicksPercent: Int = 100,
                composition: CompositionVariant = .baseline, alliedBaseDamage: Bool,
                enemySpecialAmmoPercent: Int = 100) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayNameKey = displayNameKey
        self.enemyBehavior = enemyBehavior
        self.telegraphTicksPercent = telegraphTicksPercent
        self.composition = composition
        self.alliedBaseDamage = alliedBaseDamage
        self.enemySpecialAmmoPercent = enemySpecialAmmoPercent
    }

    /// The behaviour of the game before difficulty content existed: the
    /// authored composition, standard behaviour, allied base damage on.
    public static let standard = DifficultyDefinition(
        id: "standard", displayNameKey: "difficulty.standard.name",
        enemyBehavior: .standard, alliedBaseDamage: true)

    /// The composition an archetype list becomes under this variant.
    public func apply(toComposition composition: [String]) -> [String] {
        switch self.composition {
        case .baseline: return composition
        case .forgiving:
            return composition.map { id in
                if id.hasSuffix("_c") { return String(id.dropLast(2)) + "_a" }
                if id.hasSuffix("_d") { return String(id.dropLast(2)) + "_b" }
                return id
            }
        case .advanced:
            var promotable = 0
            return composition.map { id in
                guard id.hasSuffix("_a") || id.hasSuffix("_b") else { return id }
                promotable += 1
                guard promotable % 3 == 0 else { return id }
                return String(id.dropLast(2)) + (id.hasSuffix("_a") ? "_c" : "_d")
            }
        }
    }

    /// Telegraph duration under this difficulty: scaled, floored (§10.6).
    public func telegraphTicks(authored: Int) -> Int {
        max(StageValidator.telegraphFairnessFloor, authored * telegraphTicksPercent / 100)
    }
}

public enum DifficultyValidator {
    public static func validate(_ def: DifficultyDefinition, known: StageValidator.KnownIDs = .reference) -> [String] {
        var issues: [String] = []
        if def.schemaVersion != 1 { issues.append("schema_version \(def.schemaVersion) unsupported (expected 1)") }
        if def.id.isEmpty { issues.append("id is empty") }
        else if !known.difficulties.contains(def.id) { issues.append("unknown difficulty id '\(def.id)'") }
        issues += def.enemyBehavior.validationIssues().map { "enemy_behavior: \($0)" }
        if !(10...400).contains(def.telegraphTicksPercent) { issues.append("telegraph_ticks_percent \(def.telegraphTicksPercent) outside 10…400") }
        if !(0...400).contains(def.enemySpecialAmmoPercent) { issues.append("enemy_special_ammo_percent \(def.enemySpecialAmmoPercent) outside 0…400") }
        return issues
    }
}
