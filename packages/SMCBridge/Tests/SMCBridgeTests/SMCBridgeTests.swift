import Testing
import SharedModels
@testable import SMCBridge

@Test func mockControllerWritesFanTarget() throws {
    let controller = MockSMCController(
        snapshot: SensorSnapshot(
            timestamp: .now,
            temperatures: [.init(name: "cpu", celsius: 70)],
            fans: [.init(id: 0, currentRPM: 2000)],
            isExternalDisplayConnected: false,
            isClamshellMode: false
        ),
        descriptor: .init(
            identifier: "MacBookPro16,1",
            fanCapabilities: [.init(id: 0, minimumRPM: 1800, maximumRPM: 5500)]
        )
    )

    try controller.setFanRPM(2800, fanID: 0)
    let snapshot = try controller.readSnapshot()

    #expect(snapshot.fans.first?.targetRPM == 2800)
}

@Test func intelRPMEncodingUsesFPE2StylePayload() {
    let data = IntelSMCValueDecoder.encodeRPM(2800)
    #expect(data.count == 2)
}
