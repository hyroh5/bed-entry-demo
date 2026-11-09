import Foundation
import Observation

/// 각도 범위별 점수 (min 이상 max 미만, 마지막 범위는 max 포함).
struct ScoreBand: Codable, Hashable, Identifiable {
    var id = UUID()
    var minDeg: Double
    var maxDeg: Double
    var score: Double

    enum CodingKeys: String, CodingKey { case minDeg, maxDeg, score }
}

/// 고정 룰 설정. 모든 값은 초기 가설이며 룰 설정 화면에서 수정한다.
struct RuleConfig: Codable, Equatable {
    // 가중치 (합으로 정규화)
    var weightPosture = 40.0
    var weightMotion = 35.0
    var weightBedtime = 25.0

    // A. 기기 자세 — 임시 기준값
    var screenTiltBands: [ScoreBand] = [
        ScoreBand(minDeg: 0, maxDeg: 20, score: 10),     // 거의 수평, 화면 위 (책상 위 등)
        ScoreBand(minDeg: 20, maxDeg: 65, score: 20),    // 앉거나 서서 들고 보는 일반적 각도
        ScoreBand(minDeg: 65, maxDeg: 100, score: 55),   // 수직에 가까움
        ScoreBand(minDeg: 100, maxDeg: 180, score: 90),  // 화면이 아래를 향함 (누워서 위로 들고 보기)
    ]
    var lateralTiltBands: [ScoreBand] = [
        ScoreBand(minDeg: 0, maxDeg: 50, score: 0),
        ScoreBand(minDeg: 50, maxDeg: 90, score: 70),    // 옆으로 눕힌 기기
    ]
    var lateralMinHorizontalG = 0.6

    // B. 움직임 안정성
    var motionWindowSeconds = 10.0
    var accMeanLow = 0.02      // g, 이하이면 만점
    var accMeanHigh = 0.10     // g, 이상이면 0점
    var accVarLow = 0.0005
    var accVarHigh = 0.01
    var gyroMeanLow = 0.08     // rad/s
    var gyroMeanHigh = 0.5
    var gyroVarLow = 0.005
    var gyroVarHigh = 0.1
    var stableAccThreshold = 0.05   // 샘플 단위 안정 판정
    var stableGyroThreshold = 0.35
    var stableDurationForFull = 60.0
    var motionSubWeightAcc = 0.4
    var motionSubWeightGyro = 0.4
    var motionSubWeightDuration = 0.2

    // C. 목표 취침 시간 (분)
    var bedtimeWindowBeforeMinutes = 120.0
    var bedtimeWindowAfterMinutes = 240.0
    var bedtimePlateauMinutes = 30.0

    // 판정
    var threshold = 70.0
    var holdSeconds = 60.0
    var minDataRatio = 0.8

    // 위치 게이트
    var maxLocationAccuracy = 100.0
    var maxLocationAgeSeconds = 300.0

    // 정답 응답 시 함께 저장할 직전 구간(초)
    var labelContextSeconds = 30.0

    /// 설정 내용 기반 버전 문자열 (같은 설정이면 같은 값).
    var version: String {
        guard let data = try? Self.sortedEncoder.encode(self) else { return "unknown" }
        var hash: UInt32 = 2_166_136_261
        for byte in data {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    var json: String {
        guard let data = try? Self.sortedEncoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static var sortedEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

struct AppSettings: Codable, Equatable {
    var targetBedtimeMinutes = 23 * 60 + 30
    var homeLatitude: Double?
    var homeLongitude: Double?
    var homeRadius = 150.0
    var locationGateEnabled = true
    var samplingHz = 20.0
}

/// UserDefaults에 JSON으로 저장되는 설정 저장소.
@Observable @MainActor
final class SettingsStore {
    var app: AppSettings { didSet { Self.save(app, key: Self.appKey) } }
    var rules: RuleConfig { didSet { Self.save(rules, key: Self.rulesKey) } }

    private static let appKey = "settings.app.v1"
    private static let rulesKey = "settings.rules.v1"

    init() {
        app = Self.load(AppSettings.self, key: Self.appKey) ?? AppSettings()
        rules = Self.load(RuleConfig.self, key: Self.rulesKey) ?? RuleConfig()
    }

    func resetRules() { rules = RuleConfig() }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
