import Testing
@testable import SharedModels

@Test func highestTemperatureReturnsMaxReading() {
    let snapshot = SensorSnapshot(
        timestamp: .now,
        temperatures: [
            .init(name: "cpu", celsius: 82),
            .init(name: "gpu", celsius: 76),
        ],
        fans: [],
        isExternalDisplayConnected: false,
        isClamshellMode: false
    )

    #expect(snapshot.highestTemperature == 82)
}
