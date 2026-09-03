import Testing
import GameCore
@testable import GameApplication

@Suite struct BootstrapSessionTests {
    @Test func defaultsToProvisionalArenaBaseline() {
        #expect(BootstrapSession().arena == .universal)
    }
}
