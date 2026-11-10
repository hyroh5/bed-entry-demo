import Foundation
import Testing
@testable import SleepDemo

@MainActor
struct CollectionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func inBedFollowsLatestTransition() {
        let times = [0.0, 1, 2, 3, 4, 5].map { t0.addingTimeInterval($0) }
        let transitions = [(t0.addingTimeInterval(1), false), (t0.addingTimeInterval(3.5), true)]
        let v = ExportService.inBedValues(at: times, transitions: transitions)
        #expect(v == [nil, false, false, false, true, true])
        #expect(ExportService.inBedValues(at: times, transitions: []).allSatisfy { $0 == nil })
    }

    @Test func sampleCodecRoundTrip() {
        let s = MotionSample(t: t0, pitch: 0.1, roll: 0.2, yaw: 0.3, gx: 0, gy: -1, gz: 0,
                             ax: 0.01, ay: 0.02, az: 0.03, rx: 0.1, ry: 0.2, rz: 0.3, battery: .charging)
        let decoded = SampleCodec.decode(SampleCodec.encode([s, s]))
        #expect(decoded.count == 2)
        #expect(decoded[0].t == t0 && decoded[0].gy == -1 && decoded[0].battery == .charging)
    }
}
