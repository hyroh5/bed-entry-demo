import Foundation

/// 센서 샘플 1개. 저장(배치)·내보내기·실시간 분석에 공통으로 쓴다.
struct MotionSample: Codable, Sendable {
    var t: Date
    // attitude (rad)
    var pitch: Double
    var roll: Double
    var yaw: Double
    // gravity (g)
    var gx: Double
    var gy: Double
    var gz: Double
    // userAcceleration (g)
    var ax: Double
    var ay: Double
    var az: Double
    // rotationRate (rad/s)
    var rx: Double
    var ry: Double
    var rz: Double
    var battery: BatteryStatus

    var accMagnitude: Double { (ax * ax + ay * ay + az * az).squareRoot() }
    var gyroMagnitude: Double { (rx * rx + ry * ry + rz * rz).squareRoot() }
}

enum BatteryStatus: String, Codable, Sendable {
    case charging, full, unplugged, unknown

    var label: String {
        switch self {
        case .charging: "충전 중"
        case .full: "완충"
        case .unplugged: "미충전"
        case .unknown: "알 수 없음"
        }
    }
}

enum GateStatus: String, Codable, Sendable {
    case pass = "PASS"
    case blocked = "BLOCKED"
    case unknown = "UNKNOWN"
    case disabled = "DISABLED"

    var label: String {
        switch self {
        case .pass: "통과"
        case .blocked: "차단"
        case .unknown: "알 수 없음"
        case .disabled: "제한 해제"
        }
    }
}

enum BedState: String, Codable, Sendable {
    case blocked = "BLOCKED"
    case unknown = "UNKNOWN"
    case notInBed = "NOT_IN_BED"
    case possiblyInBed = "POSSIBLY_IN_BED"
}

/// 최근 구간(윈도우) 통계량.
struct WindowFeatures: Codable, Sendable {
    var sampleCount: Int
    var windowSeconds: Double
    var accMean: Double
    var accVar: Double
    var gyroMean: Double
    var gyroVar: Double
    /// 윈도우 평균 중력 벡터(정규화)
    var gravityX: Double
    var gravityY: Double
    var gravityZ: Double
    /// 화면 기울기: 0° = 화면이 위(하늘)를 향해 수평, 90° = 수직, 180° = 화면이 아래(바닥)를 향함
    var screenTiltDeg: Double
    /// 측면 기울기: 0° = 세로 방향으로 섬, 90° = 옆으로 눕힘 (중력의 x·y 성분 기준)
    var lateralTiltDeg: Double
    /// 중력의 화면 평면(x·y) 성분 크기. 작으면 측면 기울기가 의미 없다.
    var horizontalG: Double
    /// 움직임이 안정 임계값 아래로 연속 유지된 시간(초)
    var stableDuration: Double
}

/// 한 번의 판정 결과.
struct Assessment: Sendable {
    var timestamp: Date
    var state: BedState
    /// 유지 시간 조건을 적용하기 전 상태
    var rawState: BedState
    var total: Double?
    var posture: Double?
    var motion: Double?
    var bedtime: Double?
    var locationGate: GateStatus
    var appActive: Bool
    var secondsAboveThreshold: Double
    var reason: String
}
