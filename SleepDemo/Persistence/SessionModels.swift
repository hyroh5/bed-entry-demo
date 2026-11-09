import Foundation
import SwiftData

/// 측정 세션. 집 좌표는 개인정보이므로 저장하지 않고 반경·게이트 설정만 남긴다.
@Model
final class MeasurementSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var targetBedtimeMinutes: Int
    var locationGateEnabled: Bool
    var homeRadius: Double
    var initialLocationGate: String
    var samplingHz: Double
    var ruleVersion: String
    var ruleConfigJSON: String

    @Relationship(deleteRule: .cascade, inverse: \SampleBatch.session) var batches: [SampleBatch] = []
    @Relationship(deleteRule: .cascade, inverse: \ScorePoint.session) var scores: [ScorePoint] = []
    @Relationship(deleteRule: .cascade, inverse: \UserLabel.session) var labels: [UserLabel] = []

    init(startedAt: Date, targetBedtimeMinutes: Int, locationGateEnabled: Bool, homeRadius: Double,
         initialLocationGate: String, samplingHz: Double, ruleVersion: String, ruleConfigJSON: String) {
        self.id = UUID()
        self.startedAt = startedAt
        self.targetBedtimeMinutes = targetBedtimeMinutes
        self.locationGateEnabled = locationGateEnabled
        self.homeRadius = homeRadius
        self.initialLocationGate = initialLocationGate
        self.samplingHz = samplingHz
        self.ruleVersion = ruleVersion
        self.ruleConfigJSON = ruleConfigJSON
    }

    var ruleConfig: RuleConfig? {
        try? JSONDecoder().decode(RuleConfig.self, from: Data(ruleConfigJSON.utf8))
    }

    var sampleCount: Int { batches.reduce(0) { $0 + $1.count } }

    var sortedScores: [ScorePoint] { scores.sorted { $0.timestamp < $1.timestamp } }
    var sortedLabels: [UserLabel] { labels.sorted { $0.timestamp < $1.timestamp } }

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

/// 1초 간격 판정 기록 + 그 시점의 윈도우 통계량.
@Model
final class ScorePoint {
    var timestamp: Date
    var state: String
    var rawState: String
    var total: Double?
    var posture: Double?
    var motion: Double?
    var bedtime: Double?
    var locationGate: String
    var appActive: Bool
    var battery: String
    var ruleVersion: String
    var featuresData: Data?
    var session: MeasurementSession?

    init(assessment a: Assessment, features: WindowFeatures?, battery: BatteryStatus, ruleVersion: String) {
        timestamp = a.timestamp
        state = a.state.rawValue
        rawState = a.rawState.rawValue
        total = a.total
        posture = a.posture
        motion = a.motion
        bedtime = a.bedtime
        locationGate = a.locationGate.rawValue
        appActive = a.appActive
        self.battery = battery.rawValue
        self.ruleVersion = ruleVersion
        featuresData = features.flatMap { try? JSONEncoder().encode($0) }
    }

    var features: WindowFeatures? {
        featuresData.flatMap { try? JSONDecoder().decode(WindowFeatures.self, from: $0) }
    }
}

/// 사용자 정답 응답 + 응답 시점 예측 + 직전 구간 원시 데이터.
@Model
final class UserLabel {
    var id: UUID
    var timestamp: Date
    var inBed: Bool
    var predictedState: String
    var predictedRawState: String
    var total: Double?
    var posture: Double?
    var motion: Double?
    var bedtime: Double?
    var locationGate: String
    var ruleVersion: String
    var featuresData: Data?
    var contextSeconds: Double
    @Attribute(.externalStorage) var contextSamples: Data
    var session: MeasurementSession?

    init(inBed: Bool, timestamp: Date, assessment a: Assessment?, features: WindowFeatures?,
         context: [MotionSample], contextSeconds: Double, ruleVersion: String) {
        id = UUID()
        self.timestamp = timestamp
        self.inBed = inBed
        predictedState = (a?.state ?? .unknown).rawValue
        predictedRawState = (a?.rawState ?? .unknown).rawValue
        total = a?.total
        posture = a?.posture
        motion = a?.motion
        bedtime = a?.bedtime
        locationGate = (a?.locationGate ?? .unknown).rawValue
        self.ruleVersion = ruleVersion
        featuresData = features.flatMap { try? JSONEncoder().encode($0) }
        self.contextSeconds = contextSeconds
        contextSamples = SampleCodec.encode(context)
    }

    var features: WindowFeatures? {
        featuresData.flatMap { try? JSONDecoder().decode(WindowFeatures.self, from: $0) }
    }

    var decodedContext: [MotionSample] { SampleCodec.decode(contextSamples) }

    /// 예측이 NOT_IN_BED / POSSIBLY_IN_BED일 때만 오분류를 판단한다 (BLOCKED·UNKNOWN은 nil).
    var isMisclassified: Bool? {
        switch BedState(rawValue: predictedState) {
        case .possiblyInBed: !inBed
        case .notInBed: inBed
        default: nil
        }
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
