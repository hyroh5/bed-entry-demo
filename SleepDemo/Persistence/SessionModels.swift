import Foundation
import SwiftData

/// 측정 세션. 원시 센서 샘플, 상태 전환, 위치 기록을 묶는다.
@Model
final class MeasurementSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var samplingHz: Double

    @Relationship(deleteRule: .cascade, inverse: \SampleBatch.session) var batches: [SampleBatch] = []
    @Relationship(deleteRule: .cascade, inverse: \UserLabel.session) var labels: [UserLabel] = []
    @Relationship(deleteRule: .cascade, inverse: \LocationRecord.session) var locations: [LocationRecord] = []

    init(startedAt: Date, samplingHz: Double) {
        self.id = UUID()
        self.startedAt = startedAt
        self.samplingHz = samplingHz
    }

    var sampleCount: Int { batches.reduce(0) { $0 + $1.count } }

    var sortedLabels: [UserLabel] { labels.sorted { $0.timestamp < $1.timestamp } }
    var sortedLocations: [LocationRecord] { locations.sorted { $0.timestamp < $1.timestamp } }

    var allSamples: [MotionSample] {
        batches.sorted { $0.startTime < $1.startTime }.flatMap { SampleCodec.decode($0.payload) }
    }
}

/// 원시 센서 샘플 묶음 (배치 저장).
@Model
final class SampleBatch {
    var startTime: Date
    var endTime: Date
    var count: Int
    @Attribute(.externalStorage) var payload: Data
    var session: MeasurementSession?

    init(samples: [MotionSample]) {
        startTime = samples.first?.t ?? Date()
        endTime = samples.last?.t ?? Date()
        count = samples.count
        payload = SampleCodec.encode(samples)
    }
}

/// 상태 전환 기록: 사용자가 상태 슬라이드를 바꾼 시각과 새 상태.
@Model
final class UserLabel {
    var id: UUID
    var timestamp: Date
    var inBed: Bool
    var session: MeasurementSession?

    init(inBed: Bool, timestamp: Date) {
        id = UUID()
        self.timestamp = timestamp
        self.inBed = inBed
    }
}

/// 위치 기록. 집이 설정돼 있으면 그 시점의 집까지 거리도 남긴다.
@Model
final class LocationRecord {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var distanceToHome: Double?
    var session: MeasurementSession?

    init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double, distanceToHome: Double?) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.distanceToHome = distanceToHome
    }
}

enum SampleCodec {
    static func encode(_ samples: [MotionSample]) -> Data {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return (try? e.encode(samples)) ?? Data()
    }

    static func decode(_ data: Data) -> [MotionSample] {
        (try? PropertyListDecoder().decode([MotionSample].self, from: data)) ?? []
    }
}
