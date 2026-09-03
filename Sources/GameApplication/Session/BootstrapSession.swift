import GameCore

/// M0 bootstrap use case: hands the presentation layer everything it needs to
/// show the empty universal arena. Grows into real session flow in M1.
public struct BootstrapSession: Sendable {
    public let arena: ArenaSpecification

    public init(arena: ArenaSpecification = .universal) {
        self.arena = arena
    }
}
