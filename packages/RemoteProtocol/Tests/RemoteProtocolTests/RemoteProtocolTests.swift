import Foundation
import Testing
@testable import RemoteProtocol

@Test func pairingResponseRoundTripsThroughJSON() throws {
    let response = PairingConfirmResponse(state: .paired, token: "token-123")

    let encoded = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(PairingConfirmResponse.self, from: encoded)

    #expect(decoded.state == .paired)
    #expect(decoded.token == "token-123")
}
