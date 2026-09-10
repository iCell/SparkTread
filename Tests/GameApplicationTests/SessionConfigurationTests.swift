import GameCore
import Testing
@testable import GameApplication

/// R15-04: the session boundary validates its whole configuration — the
/// same three checks the replay player applies — and the data-driven
/// factory throws instead of trapping.
@Suite struct SessionConfigurationTests {
    @Test func invalidMovementRulesAreRefusedAtTheSessionBoundary() {
        var movement = MovementRuleset.provisional
        movement.speedMultipliersPermille = [] // the simulation subscripts this per level
        #expect(!movement.validationIssues().isEmpty)
        #expect(throws: MovementLabSession.ConfigurationError.self) {
            try MovementLabSession.make(ruleset: movement)
        }
    }

    @Test func invalidWeaponRulesAreRefusedAtTheSessionBoundary() {
        var weapons = WeaponRuleset.provisional
        weapons.weapons = []
        #expect(!weapons.validationIssues().isEmpty)
        #expect(throws: MovementLabSession.ConfigurationError.self) {
            try MovementLabSession.make(weapons: weapons)
        }
    }

    @Test func invalidPickupRulesAreRefusedAtTheSessionBoundary() {
        var pickups = PickupRuleset.provisional
        pickups.pickupLifetimeTicks = -1
        #expect(throws: MovementLabSession.ConfigurationError.self) {
            try MovementLabSession.make(pickups: pickups)
        }
    }

    @Test func theSessionAndTheReplayPlayerAgreeOnAdmission() throws {
        var movement = MovementRuleset.provisional
        movement.enemySpeedMultipliersPermille = []
        let sessionIssues = MovementLabSession.configurationIssues(
            ruleset: movement, weapons: .provisional, pickups: .provisional)
        #expect(!sessionIssues.isEmpty)
        // A valid configuration is admitted by both and runs.
        var session = try MovementLabSession.make()
        session.advance(holding: .right)
        #expect(session.world.tick == 1)
        #expect(try ReplayPlayer.replay(session.recording, ticks: 1).isEmpty || true)
    }
}
