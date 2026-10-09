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
    /// R5.12 (owner 2026-10-09): the reserve tanks a new run starts with —
    /// 5 / 3 / 1 for casual / standard / veteran — and the percent scale on
    /// every stage's random drop chance (150 / 100 / 50). Absent in a file
    /// means 3 and 100.
    public var startingLives: Int
    public var dropChancePercentScale: Int

    public init(schemaVersion: Int = 1, id: String, displayNameKey: String,
                enemyBehavior: EnemyBehaviorProfile, telegraphTicksPercent: Int = 100,
                composition: CompositionVariant = .baseline, alliedBaseDamage: Bool,
                enemySpecialAmmoPercent: Int = 100, startingLives: Int = 3, dropChancePercentScale: Int = 100) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayNameKey = displayNameKey
        self.enemyBehavior = enemyBehavior
        self.telegraphTicksPercent = telegraphTicksPercent
        self.composition = composition
        self.alliedBaseDamage = alliedBaseDamage
        self.enemySpecialAmmoPercent = enemySpecialAmmoPercent
        self.startingLives = startingLives
        self.dropChancePercentScale = dropChancePercentScale
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayNameKey, enemyBehavior, telegraphTicksPercent, composition,
             alliedBaseDamage, enemySpecialAmmoPercent, startingLives, dropChancePercentScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        displayNameKey = try c.decode(String.self, forKey: .displayNameKey)
        enemyBehavior = try c.decode(EnemyBehaviorProfile.self, forKey: .enemyBehavior)
        telegraphTicksPercent = try c.decodeIfPresent(Int.self, forKey: .telegraphTicksPercent) ?? 100
        composition = try c.decodeIfPresent(CompositionVariant.self, forKey: .composition) ?? .baseline
        alliedBaseDamage = try c.decode(Bool.self, forKey: .alliedBaseDamage)
        enemySpecialAmmoPercent = try c.decodeIfPresent(Int.self, forKey: .enemySpecialAmmoPercent) ?? 100
        startingLives = try c.decodeIfPresent(Int.self, forKey: .startingLives) ?? 3
        dropChancePercentScale = try c.decodeIfPresent(Int.self, forKey: .dropChancePercentScale) ?? 100
    }

    /// A stage's random drop chance under this difficulty, capped at 100.
    public func dropChancePercent(authored: Int) -> Int {
        min(100, authored * dropChancePercentScale / 100)
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
        if !(0...99).contains(def.startingLives) { issues.append("startingLives \(def.startingLives) outside 0…99") }
        if !(0...400).contains(def.dropChancePercentScale) { issues.append("dropChancePercentScale \(def.dropChancePercentScale) outside 0…400") }
        return issues
    }
}
