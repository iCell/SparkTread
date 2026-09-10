/// Terrain passability profiles (plan §7.5, §10.4; ADR-0016): the
/// equipment a tank carries selects how terrain treats it. `amphibious`
/// (AmphiTank) crosses water; `traction` (AntiSkid) does not slide on ice;
/// everything else is `normal`. Players and AI use the same rules.
public enum TraversalProfile: String, Codable, Sendable, CaseIterable {
    case normal, amphibious, traction

    public init(equipmentID: String?) {
        switch equipmentID {
        case "amphi_tank": self = .amphibious
        case "anti_skid": self = .traction
        default: self = .normal
        }
    }
}

extension TerrainKind {
    /// Whether the kind blocks a tank of the given profile.
    public func blocksTank(profile: TraversalProfile) -> Bool {
        self == .water ? profile != .amphibious : blocksTanksByDefault
    }
}
